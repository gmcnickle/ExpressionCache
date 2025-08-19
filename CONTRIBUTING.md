# Contributing to ExpressionCache

First off, thank you for considering contributing — your help makes this project better for everyone. 🎉

## Ways to Contribute

- **Bug reports** — open an issue with steps to reproduce.  
- **Feature requests** — share your idea in [Discussions](https://github.com/gmcnickle/ExpressionCache/discussions) or as an issue.  
- **Code contributions** — submit a pull request (PR) with improvements, fixes, or new providers.  
- **Documentation** — help improve the README, examples, or comments.  

## Development Setup

1. Clone the repo:
   ```powershell
   git clone https://github.com/gmcnickle/ExpressionCache.git
   cd ExpressionCache
   ```

2. Import the module (local dev):
   ```powershell
   Import-Module "$PSScriptRoot/src/ExpressionCache.psd1" -Force
   ```

3. Run the test suite:
   ```powershell
   pwsh ./tests/run-tests.ps1
   ```

> Requires PowerShell 5.1+ or 7.x. Tests use [Pester](https://pester.dev/) v5+.

## Coding Guidelines

- Keep functions small and focused.  
- Prefer **parameters** over ambient variables inside scriptblocks.  
- Follow existing naming conventions (`Verb-Noun`).  
- Add or update **tests** for every change.  

## Pull Request Process

1. Fork the repository and create your branch from `main`.  
2. Make your changes, ensuring tests pass.  
3. Update documentation if needed (README, examples).  
4. Open a PR with a clear description of what changed and why.  

For larger changes, consider starting a [Discussion](https://github.com/gmcnickle/ExpressionCache/discussions) before writing code.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE.md) for code and [CC BY 4.0](LICENSE-CC-BY.md) for documentation and non-code content.
