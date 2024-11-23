# OTPless Erlang - Beamer

Beamer is a tool that allows you to install and manage multiple versions of
OTPless Erlang on the same machine.

```sh
curl -o- https://raw.githubusercontent.com/otpless-erlang/beamer/v0.0.1/install.sh | bash
```
```
beamer install x.y.z
beamer use x.y.z
beam -v
```

Inspired by [NVM](https://github.com/nvm-sh/nvm), Beamer is designed to be
installed per-user, and invoked per-shell. nvm works on any POSIX-compliant
shell (sh, dash, ksh, zsh, bash), in particular on these platforms: Linux,
macOS, and Windows WSL.
