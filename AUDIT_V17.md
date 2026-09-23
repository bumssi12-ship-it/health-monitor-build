# Health Monitor V17 One-Click Build Gate

V17 deliberately freezes application feature expansion until the first real
Apple SDK build is executed. The principal quality improvement is the Windows
to GitHub to macOS delivery path.

## Pipeline changes

1. One downloadable ZIP contains the complete canonical source and launcher.
2. `START.cmd` is the only file the Windows user needs to run after extraction.
3. Windows PowerShell 5.1 syntax is checked before any GitHub mutation.
4. Native Git/GitHub commands distinguish expected non-zero probe results from
   fatal command failures.
5. A missing GitHub repository is treated as the normal create path.
6. Re-running from a fresh ZIP against an existing repository preserves remote
   history using `git reset --mixed origin/main` while keeping the extracted
   working tree.
7. Build failure no longer prevents log collection.
8. GitHub Actions logs and the uploaded build artifact are downloaded
   automatically when available.
9. `LAST_BUILD_STATUS.txt` contains the run ID, URL, SHA, conclusion, and local
   diagnostic paths.
10. XcodeGen's existing post-generation Watch embed patch remains active.
    CI now independently verifies that the generated project uses the expected
    PlugIns destination for the embedded Watch app.

## Application status

V16 application behavior is retained, with build number 17. No speculative
feature expansion was added before the real Xcode gate.

## Remaining gates

- Windows V17 one-click pipeline execution
- actual macOS-26 Xcode compilation
- paired iPhone/Apple Watch HealthKit + WatchConnectivity runtime tests
- signing/TestFlight
