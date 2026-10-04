# Phase 1: Mac Camera Extension with test picture - Execution Plan

## 1. Goal
Prove the Mac side end-to-end with a placeholder frame.

## 2. Steps
1. Move the built host app to `/Applications` and run it.
2. Click install extension from the host app UI.
3. Approve the extension in System Settings -> Privacy and Security.
4. Open Photo Booth and verify the virtual camera appears in the Camera menu.
5. In Xcode, modify the template pattern logic in the extension to output a custom "No phone connected" frame.
6. Re-build, re-install, and verify the placeholder frame shows in Photo Booth and QuickTime.

## 3. Success Criteria
- The custom placeholder frame is visible in Mac camera consumer apps (Photo Booth, QuickTime).
