class_name ShopItem
extends Resource
## One thing the shop sells (ShopCatalog): which tab, its price, and what it changes on the look —
## a colour, and for some a shape (a hat style, a ball style…). Values live in data/shop_catalog.tres.

enum Tab { HAT, SHIRT, PANTS, SHOES, BALL, CLUB, TRAIL }

@export var id := ""
@export var tab: Tab
@export var title := ""
@export var price: int
@export var color: Color ## the hat / shirt / trousers / shoes / ball / club colour
@export var accent := Color.WHITE ## a second tone (the ball's stripe)
@export var style := 0 ## the look's style for its tab (CharacterLook: hat_style, shirt_style, …, trail_style)
