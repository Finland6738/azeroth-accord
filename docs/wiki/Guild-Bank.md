# Guild bank

> Available from the bank version (`v0.9.0`). The addon has not been checked in the real game yet: the first tests are with the owner's guild (the in-game check is [docs/checklists/M5.md](https://github.com/Finland6738/azeroth-accord/blob/main/docs/checklists/M5.md)).

- The game shows the bank only at the vault. Whenever a guildmate with the addon opens it, the addon saves what each tab holds and shares it, so the **Bank** view works anywhere. Each tab shows how old its contents are.
- Tabs that your rank cannot see in the game stay hidden in the addon too.
- **Logs and donations**: deposits and withdrawals are collected over time; the donations list shows who helped the guild in the last 30 days, the last year and in total.
- **Requests**: ask for an item or gold (*Withdraw*), offer an item (*Deposit*) or pledge a *Donation*. Officers approve or reject it and mark it as fulfilled; handing the item over happens in the game (mail, trade or the vault).

## Who sees what

- What you see in the vault is shared with the guild so that a guildmate who never visits the vault sees it too, as old as your visit.
- The game does not tell the addon which ranks may see a tab, only whether *your* rank can. So a tab you read is shown to members of your rank and above. A tab read by an **officer** is shared with officers only (on the officer channel) and never reaches the members' computers. If every rank may see a tab but only officers have opened the vault, members see that tab once a member has opened it too.

## The Bank view

Open it with the **Bank** button of the panel or `/accord bank`.

- **Tabs**: one button per tab you may see, the guild's money and how old it is, and the tab laid out like in the game (14 columns of 7 slots). Under the tab buttons you read *seen 2 h ago by Bob*: the age of the contents and the guildmate whose addon read them. Hover an item for its tooltip.
- **Items**: one row per item over all the tabs you may see, with the total and where it is. The search box of the panel filters by item name, item number or tab name.
- With nothing to show yet, the view says so: somebody must open the vault once.

## Logs, donations and money

- **Log**: who deposited or withdrew what, newest first. The game keeps only a short history and shows it only at the vault; the addon adds every visit of a guildmate with the addon to the history, without listing the same event twice, so it grows beyond the game's. Search by name or item.
- **Donations**: what each player deposited (gold and items) in the last 30 days, the last 365 days or ever, all the characters of a player together. Withdrawals and repairs do not count. The list is visible to every member (the owner may restrict it to officers).
- **Money**: how the guild's money changed over the last 30 days, from what the addons have seen.

## Requests

In the **Requests** mode of the Bank view you can:

- **Withdraw**: ask for an item from the bank, or for gold; **Deposit**: offer an item; **Donation**: promise items or gold. Paste an item link (or write its number) in the item box, or leave it empty for gold; add how many (or how many gold pieces) and a reason, then press *Send request*. You can have five open requests at once.
- Every guildmate sees every request. You can **cancel** your own while it is still open.
- **Officers** answer with *Approve*, *Reject* (the reason box becomes the reason of the rejection) and *Fulfilled*. Hover over a row to read its history. Only officers can change a request's status: the other addons ignore anything else.
- The addon never moves items or gold: after an approval the item reaches you by mail, trade or at the vault, as the officers decide.

## For officers: the inbox and the notices

- A red mark with a number appears on the Accord tab of the guild window (and "Bank (n)" on the panel button) when requests are waiting for you. Members never see it.
- The **Inbox** mode lists what waits for an officer, oldest first: open requests to approve or reject, approved ones to mark as *Fulfilled*. When the bank log shows the matching movement (the requester took the item out, or deposited it, or the gold), the row says *Looks delivered*; you still mark it yourself, because handing over stays manual.
- You get one chat line when a new request arrives; the requester gets one when you approve, reject or fulfil it. Notices are never repeated after a reload, and the first time the addon runs it does not announce the requests that already exist.
