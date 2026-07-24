# Hermes development stack for Coolify

This directory contains the deployable Compose application and its custom
remote-development image. The complete setup and operating procedure is in
[`PLAN.md`](PLAN.md).

Quick validation:

```bash
bash tests/test_stack.sh
```

Required Coolify variables are documented in `.env.example`. Never commit a
populated `.env` or provider credentials.
