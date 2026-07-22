# Contributing

Thanks for your interest in CyberDeck!

## Development Setup

1. Fork the repo and clone it
2. Make changes on a branch
3. Test on a real Pi 4 if possible (or at minimum run `scripts/verify.sh`)
4. Submit a pull request

## Code Style

- Shell scripts: follow ShellCheck recommendations
- HTML/CSS/JS: match the existing cyberdeck aesthetic
- Keep it simple — no build tools, no npm in production, no external CDNs

## Reporting Issues

Open a GitHub issue with:
- What you expected
- What happened
- Output of `sudo bash scripts/status.sh`
- Your Pi model and OS version (`cat /etc/os-release`)

## Git Authentication

GitHub no longer accepts account passwords for `git push` over HTTPS.
Use a Personal Access Token (PAT) instead:
- GitHub → Settings → Developer settings → Personal access tokens
- Generate a token with `repo` scope
- Use it as your password when pushing
