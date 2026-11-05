# Working agreement (recorded from the product owner's instructions)

Source: instructions given by the product owner (repository owner `ADatkashov`) in the working session, 2026-11-05.

1. **Merging to `main` is pre-authorised.** The assistant opens a pull request for its own work, waits for CI to be green on the current head, and merges it into `main` itself, without asking each time.
   *Limits that stay in force:* only PRs the assistant opened for this repository; CI must be green on the head commit; no force-push, no history rewriting, no secrets or credentials committed; a failing or skipped test is never "fixed" by disabling it.
2. **Priorities are chosen by the assistant**, in order of impact on a Kazakhstan pilot, without waiting for approval between steps.
3. **The owner's part stays on mocks until the owner says otherwise.** External integrations that need the owner's accounts, keys or contracts (real SMS gateway, push credentials, licensed maps/routing, payment providers, store accounts, legal texts) are implemented behind interfaces with clearly labelled development mocks. Mocks must never pretend to be live (see `docs/product/STATUS.md`, "Mocks").
4. **No legal text is written by the assistant**; it is published through the admin console once qualified counsel supplies it.

This file records the owner's instruction; it is not a technical access-control mechanism.


Исходные сообщения владельца (дословно, включая это разрешение): `docs/product/OWNER_PROMPTS.md`.
