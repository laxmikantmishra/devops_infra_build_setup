# Worker guest scripts

The deployment module selects the installer that matches `WORKER_OS`:
- Windows: `Install-WorkerWindows.ps1`.
- Linux: `install-worker-linux.sh`, invoked by the PowerShell orchestration layer.

Both installers download a versioned ZIP through the VM's managed identity, expand it to a release directory, configure the operating-system service, start it, and verify that it is running. The application package remains responsible for bundling its runtime prerequisites and for application-level graceful shutdown and health behavior.
