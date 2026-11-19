# Guild bank

> Planned for milestone M5. Step by step: the addon already reads the vault when *you* open it (M5.1) and shares what it saw with the guild (M5.2); the Bank view follows.

- The game shows the bank only at the vault. Whenever a guildmate with the addon opens it, the addon saves what each tab holds and shares it, so the **Bank** view works anywhere. Each tab shows how old its contents are.
- Tabs that your rank cannot see in the game stay hidden in the addon too.
- **Logs and donations**: deposits and withdrawals are collected over time; the donations list shows who helped the guild in the last 30 days, the last year and in total.
- **Requests**: ask for an item or gold (*Withdraw*), offer an item (*Deposit*) or pledge a *Donation*. Officers approve or reject it and mark it as fulfilled; handing the item over happens in the game (mail, trade or the vault).

## Who sees what

- What you see in the vault is shared with the guild so that a guildmate who never visits the vault sees it too, as old as your visit.
- The game does not tell the addon which ranks may see a tab, only whether *your* rank can. So a tab you read is shown to members of your rank and above. A tab read by an **officer** is shared with officers only (on the officer channel) and never reaches the members' computers. If every rank may see a tab but only officers have opened the vault, members see that tab once a member has opened it too.
