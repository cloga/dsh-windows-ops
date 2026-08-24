// workspace-fix-plugin.template.js
// =====================================================================
// RUNTIME workspace-group repair for DSH sessions — use when the DSH app is
// RUNNING and you cannot restart: the live workspaceRegistry service updates
// the domain through its official write chain and pushes host/workspace-changed
// to the sidebar (no restart, no page refresh needed for the data change).
//
// HOW TO USE (in any DSH agent session):
//   1. Replace __SESSION_ID__ and __TARGET_CWD__ below.
//   2. Paste the `return { ... }` block into cordis_define code.host
//      (plugin: new, idPrefix: 3-6 lowercase letters, host half only).
//   3. cordis_run with the returned pluginId/packageId.
//   4. Verify in desktop.log: lines tagged [wsfix]; expect "DONE".
//      Then check the sidebar group (refresh the page if it did not update).
//
// When the app is CLOSED instead, use tools/dsh-workspace-fix.mjs (file-level,
// same official semantics, takes effect on next startup).
//
// Semantics mirrored from @deepseek-ai/dsh-workspace:
//   - detachSession: idempotent removal from record.sessionIds
//   - attachSession: validates header.cwd realpath === workspace.path, then
//     prepends to record.sessionIds and re-remembers the session path
// =====================================================================

return {
  apply(ctx) {
    const SID = '__SESSION_ID__';
    const TARGET = '__TARGET_CWD__';
    const run = async () => {
      const registry = ctx.get('workspaceRegistry');
      if (registry === undefined) throw new Error('[wsfix] workspaceRegistry service not available');
      const all = registry.list();
      console.log('[wsfix] workspaces=' + all.length);
      // Owners = record-level accounting (the getter filters by live path, so
      // a dangled session can hide from read() but must still be detached).
      const owners = all.filter((ws) => ws.record && ws.record.sessionIds.includes(SID));
      const target = all.find((ws) => String(ws.record.path).toLowerCase() === String(TARGET).toLowerCase());
      console.log('[wsfix] owners=' + JSON.stringify(owners.map((ws) => ws.id)));
      if (!target) throw new Error('[wsfix] no workspace owns target cwd ' + TARGET + ' — create one first with dsh-workspace-fix.mjs (app closed) or workspace.create');
      // Detach first, then attach: the intermediate state (unowned) is safe;
      // the reverse order would persist a both-accounted state and trip the
      // startup validator if the process dies in between.
      for (const ws of owners) {
        if (ws.id === target.id) continue;
        await ws.detachSession(SID);
        console.log('[wsfix] detached from ' + ws.id);
      }
      await target.attachSession(SID);
      console.log('[wsfix] attached to ' + target.id + ' path=' + target.record.path);
      console.log('[wsfix] DONE session=' + SID);
    };
    run().catch((e) => console.error('[wsfix] FAILED: ' + (e && e.stack ? e.stack : String(e))));
  }
};
