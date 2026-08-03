# Proven mappings

Each row is a donor that has survived contact with a real screen. The
"why it works" column is the part to keep when adapting — it explains what
the idiom is actually solving, so you can tell when it stops applying.

| Domain | Data shape | Donor | Why it works |
|---|---|---|---|
| Banking | Several accounts, one active | **Wallet card deck** | Cards peek so the count is visible without a list; the expanded one owns the screen. Fails past ~8 items. |
| Investing | Value over time vs. a benchmark | **Stocks row + sparkline** | Trend and current value in one line, so a list of them is scannable. The signed, coloured delta does the interpreting. |
| Health | One derived score | **Fitness ring / Bevel dial** | A number with no scale is meaningless; the arc supplies the scale implicitly. Delta beneath answers "is that good?". |
| Health | 3–5 peer metrics | **Activity ring trio** | Equal visual weight says "these are siblings". Adding a fourth ring is usually the moment to split the screen. |
| Fitness | Sets, reps, load per exercise | **Notes-style grouped table** | Dense, editable in place, and the row order *is* the workout order. |
| Nutrition | Today vs. targets | **Ring + macro legend** | The ring answers "am I on track", the legend answers "on what". Two questions, two elements. |
| Habits | Consecutive days | **Duolingo flame** | The streak count is the reward; the calendar is evidence. Inverting that makes it a chore chart. |
| Pets/tamagotchi | State that decays with neglect | **Tamagotchi stage** | A character communicates state faster than a gauge, and creates obligation a percentage never will. |
| Media | Large browsable catalogue | **App Store / Music shelf** | Horizontal rows by category let a big library be skimmed without a taxonomy the user has to learn. |
| Messaging | Threads with unread state | **Mail list** | Sender-first, bold-for-unread, timestamp right. Every user on earth already parses this. |
| Travel/booking | Options with tradeoffs | **Airbnb card** | Photo carries the emotional decision; price and rating carry the rational one. Both must be visible without a tap. |
| Any | A destructive or irreversible step | **Apple confirmation sheet** | The action is spelled out in the button, not "OK". The safe choice is the easy one. |

## Anti-patterns

- **The dashboard reflex.** Four equal tiles in a grid is what you build when
  you haven't decided what matters. Pick a hero.
- **Skinning.** Copying the donor's colour and radius while ignoring its
  hierarchy gets you a screen that looks derivative *and* reads badly.
- **Donor drift mid-screen.** One screen, one idiom. A card deck on top of a
  transaction list on top of a ring trio is three apps stacked.
