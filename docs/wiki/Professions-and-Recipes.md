# Professions and recipes

> Available from the professions version (milestone M3): recipe lists, **who can craft** and **Request craft**.

## Opening a member's recipes

In the **Roster** table, the **Profession 1** and **Profession 2** cells show the profession and its rank (`Alchemy 285/300` when the maximum is known). Hover a cell to see **where the information comes from** (the game, or the member's addon and how old) and click it: the **Professions** view opens on that member's recipe list. The profession lines of the **member card** do the same.

The list shows an icon and the name of every recipe the member knows, sorted by name, with the game's own tooltip when you hover a recipe. Above it you see the member, the profession and the rank, **where the list comes from and how old it is** (for example "Source: shared by the member's addon, 3 d ago"), and how many recipes match.

- **Search**: type in the search box at the top of the panel to filter by recipe name.
- **Category**: the menu offers *Recipes I know* and *Recipes I do not know* (compared with your own list of the same profession, once you have opened that profession yourself) and, when the game tells it, the recipe categories. Recipes you know too are marked "you know it".
- **Back to roster** returns to the table.

![A guildmate's recipe list: the source and age of the list, the search, a category menu, difficulty colours, the game's own tooltip and Request craft](../specs/mockups/previews/professions-recipes.webp)

## When there is no list

If the game does not give the list and the member's addon has not shared it, the panel says why and what to do: nobody who has the list is online (ask the member to open their profession window with Azeroth Accord, it is shared at once), the member does not use the addon, or the list is being requested. When you open a member's recipes and the addon does not have their list yet, it asks for it by whisper (to the member if they are online, else to an officer) and the list appears a few seconds later.

## Your own recipes

Your own recipes are shared when you open your profession window with the addon: Azeroth Accord reads the list a couple of seconds after the window opens (or changes) and publishes it to your guildmates who have the addon. It is published again only when something changed (a new recipe, a new skill rank), and at most once every 10 minutes per profession. Cooking, First Aid and Fishing are shared too, so "who can craft" finds your cook; they do not appear in the profession columns of the roster, which show the two main professions.

## Who can craft

Open the **Professions** view (`/accord professions`, or the **Professions** tab) and type the name of an item or a recipe in the search box at the right of the tabs (at least two letters; you can also paste an item link). The view lists the recipes that match and, under each one, the members who can craft it: **online members first**, then by name, with the characters of one player together (the alts a little to the right). Each line says the profession and rank and where the list comes from and how old it is. **Online only** keeps just the members who are online now. Click a member to see all their recipes; **Back** returns to the search.

The search covers the members **whose recipe list is known**: lists shared by guildmates who use Azeroth Accord, and lists the game gave you when you opened a member's recipes. If nobody is found, open a few members' recipes (the addon asks for them) and search again.

![Who can craft: the guildmates who know each recipe, online first, with the source and age of their list and a Request craft button](../specs/mockups/previews/professions-who-can-craft.webp)

*Design previews, not screenshots: drawn from the addon's own layout and texts with invented characters and items, because the addon has not been run in the game yet ([all previews](https://github.com/Finland6738/azeroth-accord/blob/main/docs/specs/mockups/previews/README.md)).*

## Request craft

Next to every recipe of an **online** member (in their list, or under the recipe in *Who can craft*) there is a **Request craft** button. It opens the chat box with a whisper to that member already written, with the recipe link in it: *"Hello! Could you craft [recipe] for me? Thank you!"*. **Azeroth Accord never sends it**: you read it, change it if you like and press Enter. The button is not shown for offline members (a whisper would not reach them), for your own recipes, or on the recipe's header line.

## If something is missing

- **The list of a member is not there**: the game does not always give recipe lists, and a member's addon shares theirs only after they open the profession window with Azeroth Accord. The panel says so, and asks for the list by itself while somebody who has it is online.
- **A recipe shows as "Recipe 1234"**: the game has not given its name yet; it appears in a moment.
- **"Who can craft" finds nobody**: it searches the members whose list is known. Open a few members' recipes (the addon asks for them) and search again.

See also the [[FAQ]].
