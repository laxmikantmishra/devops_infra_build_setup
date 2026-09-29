# Validated tool versions

Local parsing, module import, command-parameter checks, PSScriptAnalyzer, and unit tests were run with:

| Tool/module | Version |
| --- | --- |
| PowerShell | 7.6.6 |
| Az.Accounts | 5.5.3 |
| Az.Resources | 10.2.1 |
| Az.ManagedServiceIdentity | 2.0.0 |
| Az.Network | 8.2.0 |
| Az.OperationalInsights | 3.4.1 |
| Az.ApplicationInsights | 3.0.0 |
| Az.KeyVault | 6.6.1 |
| Az.Websites | 4.1.0 |
| Az.Sql | 7.1.0 |
| Az.Compute | 11.9.0 |
| Az.Storage | 9.7.2 |
| SqlServer | 22.4.5.1 |
| Pester | 6.2.0 |
| PSScriptAnalyzer | 1.25.0 |

PowerShell 7.4 is the minimum supported runtime. These exact module versions are the tested baseline; later compatible versions can be evaluated by running the same unit, analyzer, and command-contract checks before use.
