# Phase 0.5: Viability check - Execution Plan

## 1. Goal
Verify if Camera Extension can be signed and deployed on this Mac before investing effort into Android dev.

## 2. Steps
1. Create a new Xcode macOS app project.
2. Add a Camera Extension target using Xcode's built-in template.
3. Attempt to build and sign the project using the configured Apple ID.
4. If System Extension signing fails, investigate `systemextensionsctl developer on`.
5. Decide if a paid Apple Developer account is needed.
6. Note any exact errors and the macOS version for reference.

## 3. Success Criteria
- The developer knows for certain whether the extension route works on their setup without a paid account, or if they need one.
