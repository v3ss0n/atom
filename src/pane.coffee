{dirname} = require 'path'
{$, View} = require './space-pen-extensions'
_ = require 'underscore-plus'
{TelepathicObject} = require 'telepath'
PaneRow = require './pane-row'
PaneColumn = require './pane-column'

# Public: A container which can contains multiple items to be switched between.
#
# Items can be almost anything however most commonly they're {EditorView}s.
#
# Most packages won't need to use this class, unless you're interested in
# building a package that deals with switching between panes or tiems.
module.exports =
class Pane extends View

  @acceptsDocuments: true

  @content: (wrappedView) ->
    @div class: 'pane', tabindex: -1, =>
      @div class: 'item-views', outlet: 'itemViews'

  @deserialize: (state) ->
    pane = new Pane(state)
    pane.focusOnAttach = true if state.get('focused')
    pane

  activeItem: null
  items: null
  viewsByItem: null      # Views without a setModel() method are stored here

  # Private:
  initialize: (args...) ->
    @items = []
    if args[0] instanceof TelepathicObject
      @state = args[0]
      @items = _.compact(@state.get('items').getValues())
      item?.created?() for item in @getItems()
    else
      @items = args
      @state = atom.create
        deserializer: 'Pane'
        items: @items

    @handleItemEvents(item) for item in @items

    @subscribe @state.get('items'), 'changed', ({index, removedValues, insertedValues, siteId}) =>
      return if siteId is @state.siteId
      for item in removedValues
        @removeItemAtIndex(index, updateState: false)
      for item, i in insertedValues
        @addItem(itemState, index + i, updateState: false)

    @subscribe @state, 'changed', ({newValues, siteId}) =>
      return if siteId is @state.siteId
      if newValues.activeItemUri
        @showItemForUri(newValues.activeItemUri)

    @viewsByItem = new WeakMap()
    activeItemUri = @state.get('activeItemUri')
    unless activeItemUri? and @showItemForUri(activeItemUri)
      @showItem(@items[0]) if @items.length > 0

    @command 'pane:save-items', @saveItems
    @command 'pane:show-next-item', @showNextItem
    @command 'pane:show-previous-item', @showPreviousItem

    @command 'pane:show-item-1', => @showItemAtIndex(0)
    @command 'pane:show-item-2', => @showItemAtIndex(1)
    @command 'pane:show-item-3', => @showItemAtIndex(2)
    @command 'pane:show-item-4', => @showItemAtIndex(3)
    @command 'pane:show-item-5', => @showItemAtIndex(4)
    @command 'pane:show-item-6', => @showItemAtIndex(5)
    @command 'pane:show-item-7', => @showItemAtIndex(6)
    @command 'pane:show-item-8', => @showItemAtIndex(7)
    @command 'pane:show-item-9', => @showItemAtIndex(8)

    @command 'pane:split-left', => @splitLeft(@copyActiveItem())
    @command 'pane:split-right', => @splitRight(@copyActiveItem())
    @command 'pane:split-up', => @splitUp(@copyActiveItem())
    @command 'pane:split-down', => @splitDown(@copyActiveItem())
    @command 'pane:close', => @destroyItems()
    @command 'pane:close-other-items', => @destroyInactiveItems()
    @on 'focus', => @activeView?.focus(); false
    @on 'focusin', => @makeActive()

  # Private:
  afterAttach: (onDom) ->
    if @focusOnAttach and onDom
      @focusOnAttach = null
      @focus()

    return if @attached
    @attached = true
    @trigger 'pane:attached', [this]

  # Public: Focus this pane.
  makeActive: ->
    wasActive = @isActive()
    for pane in @getContainer().getPanes() when pane isnt this
      pane.makeInactive()
    @addClass('active')
    @trigger 'pane:became-active' unless wasActive

  # Public: Unfocus this pane.
  makeInactive: ->
    wasActive = @isActive()
    @removeClass('active')
    @trigger 'pane:became-inactive' if wasActive

  # Public: Returns whether this pane is currently focused.
  isActive: ->
    @getContainer()?.getActivePane() == this

  # Public: Returns the next pane, ordered by creation.
  getNextPane: ->
    panes = @getContainer()?.getPanes()
    return unless panes.length > 1
    nextIndex = (panes.indexOf(this) + 1) % panes.length
    panes[nextIndex]

  # Public: Returns all contained views.
  getItems: ->
    new Array(@items...)

  # Public: Switches to the next contained item.
  showNextItem: =>
    index = @getActiveItemIndex()
    if index < @items.length - 1
      @showItemAtIndex(index + 1)
    else
      @showItemAtIndex(0)

  # Public: Switches to the previous contained item.
  showPreviousItem: =>
    index = @getActiveItemIndex()
    if index > 0
      @showItemAtIndex(index - 1)
    else
      @showItemAtIndex(@items.length - 1)

  getActivePaneItem: ->
    @activeItem

  # Public: Returns the index of the currently active item.
  getActiveItemIndex: ->
    @items.indexOf(@activeItem)

  # Public: Switch to the item associated with the given index.
  showItemAtIndex: (index) ->
    @showItem(@itemAtIndex(index))

  # Public: Returns the item at the specified index.
  itemAtIndex: (index) ->
    @items[index]

  # Public: Focuses the given item.
  showItem: (item) ->
    return if !item? or item is @activeItem

    if @activeItem
      @activeItem.off? 'title-changed', @activeItemTitleChanged

    isFocused = @is(':has(:focus)')
    @addItem(item)
    item.on? 'title-changed', @activeItemTitleChanged
    view = @viewForItem(item)
    @itemViews.children().not(view).hide()
    @itemViews.append(view) unless view.parent().is(@itemViews)
    view.show() if @attached
    view.focus() if isFocused
    @activeItem = item
    @activeView = view
    @trigger 'pane:active-item-changed', [item]

    @state.set('activeItemUri', item.getUri?())

  # Private:
  activeItemTitleChanged: =>
    @trigger 'pane:active-item-title-changed'

  # Public: Add an additional item at the specified index.
  addItem: (item, index=@getActiveItemIndex()+1, options={}) ->
    return if _.include(@items, item)

    @state.get('items').splice(index, 0, item) if options.updateState ? true
    @items.splice(index, 0, item)
    @trigger 'pane:item-added', [item, index]
    @handleItemEvents(item)
    item

  handleItemEvents: (item) ->
    if _.isFunction(item.on)
      @subscribe item, 'destroyed', =>
        @destroyItem(item) if @state.isAlive()

  # Public: Remove the currently active item.
  destroyActiveItem: =>
    @destroyItem(@activeItem)
    false

  # Public: Remove the specified item.
  destroyItem: (item) ->
    @unsubscribe(item) if _.isFunction(item.off)
    @trigger 'pane:before-item-destroyed', [item]

    if @promptToSaveItem(item)
      @getContainer()?.itemDestroyed(item)
      @removeItem(item)
      item.destroy?()
      true
    else
      false

  # Public: Remove and delete all items.
  destroyItems: ->
    @destroyItem(item) for item in @getItems()

  # Public: Remove and delete all but the currently focused item.
  destroyInactiveItems: ->
    @destroyItem(item) for item in @getItems() when item isnt @activeItem

  # Public: Prompt the user to save the given item.
  promptToSaveItem: (item) ->
    return true unless item.shouldPromptToSave?()

    uri = item.getUri()
    chosen = atom.confirm
      message: "'#{item.getTitle?() ? item.getUri()}' has changes, do you want to save them?"
      detailedMessage: "Your changes will be lost if you close this item without saving."
      buttons: ["Save", "Cancel", "Don't Save"]

    switch chosen
      when 0 then @saveItem(item, -> true)
      when 1 then false
      when 2 then true

  # Public: Saves the currently focused item.
  saveActiveItem: =>
    @saveItem(@activeItem)

  # Public: Save and prompt for path for the currently focused item.
  saveActiveItemAs: =>
    @saveItemAs(@activeItem)

  # Public: Saves the specified item and call the next action when complete.
  saveItem: (item, nextAction) ->
    if item.getUri?()
      item.save?()
      nextAction?()
    else
      @saveItemAs(item, nextAction)

  # Public: Prompts for path and then saves the specified item. Upon completion
  # it also calls the next action.
  saveItemAs: (item, nextAction) ->
    return unless item.saveAs?

    itemPath = item.getPath?()
    itemPath = dirname(itemPath) if itemPath
    path = atom.showSaveDialogSync(itemPath)
    if path
      item.saveAs(path)
      nextAction?()

  # Public: Saves all items in this pane.
  saveItems: =>
    @saveItem(item) for item in @getItems()

  # Public:
  removeItem: (item, options) ->
    index = @items.indexOf(item)
    @removeItemAtIndex(index, options) if index >= 0

  # Public: Just remove the item at the given index.
  removeItemAtIndex: (index, options={}) ->
    item = @items[index]
    @activeItem.off? 'title-changed', @activeItemTitleChanged if item is @activeItem
    @showNextItem() if item is @activeItem and @items.length > 1
    _.remove(@items, item)
    @state.get('items').splice(index, 1) if options.updateState ? true
    @cleanupItemView(item)
    @trigger 'pane:item-removed', [item, index]

  # Public: Moves the given item to a the new index.
  moveItem: (item, newIndex) ->
    oldIndex = @items.indexOf(item)
    @items.splice(oldIndex, 1)
    @items.splice(newIndex, 0, item)
    @state.get('items').insert(newIndex, item)
    @trigger 'pane:item-moved', [item, newIndex]

  # Public: Moves the given item to another pane.
  moveItemToPane: (item, pane, index) ->
    @isMovingItem = true
    pane.addItem(item, index)
    @removeItem(item, updateState: false)
    @isMovingItem = false

  # Public: Finds the first item that matches the given uri.
  itemForUri: (uri) ->
    _.detect @items, (item) -> item.getUri?() is uri

  # Public: Focuses the first item that matches the given uri.
  showItemForUri: (uri) ->
    if item = @itemForUri(uri)
      @showItem(item)
      true
    else
      false

  # Private:
  cleanupItemView: (item) ->
    if item instanceof $
      viewToRemove = item
    else if viewToRemove = @viewsByItem.get(item)
      @viewsByItem.delete(item)

    if @items.length > 0
      if @isMovingItem and item is viewToRemove
        viewToRemove?.detach()
      else if @isMovingItem and viewToRemove?.setModel
        viewToRemove.setModel(null) # dont want to destroy the model, so set to null
        viewToRemove.remove()
      else
        viewToRemove?.remove()
    else
      if @isMovingItem and item is viewToRemove
        viewToRemove?.detach()
      else if @isMovingItem and viewToRemove?.setModel
        viewToRemove.setModel(null) # dont want to destroy the model, so set to null

      @parent().view().removeChild(this, updateState: false)

  # Private:
  viewForItem: (item) ->
    if item instanceof $
      item
    else if view = @viewsByItem.get(item)
      view
    else
      viewClass = item.getViewClass()
      view = new viewClass(item)
      @viewsByItem.set(item, view)
      view

  # Private:
  viewForActiveItem: ->
    @viewForItem(@activeItem)

  # Private:
  serialize: ->
    state = @state.clone()
    state.set('items', @items)
    state.set('focused', @is(':has(:focus)'))
    state

  # Private:
  getState: -> @state

  # Private:
  adjustDimensions: -> # do nothing

  # Private:
  horizontalGridUnits: -> 1

  # Private:
  verticalGridUnits: -> 1

  # Public: Creates a new pane above with a copy of the currently focused item.
  splitUp: (items...) ->
    @split(items, 'column', 'before')

  # Public: Creates a new pane below with a copy of the currently focused item.
  splitDown: (items...) ->
    @split(items, 'column', 'after')

  # Public: Creates a new pane left with a copy of the currently focused item.
  splitLeft: (items...) ->
    @split(items, 'row', 'before')

  # Public: Creates a new pane right with a copy of the currently focused item.
  splitRight: (items...) ->
    @split(items, 'row', 'after')

  # Private:
  split: (items, axis, side) ->
    PaneContainer = require './pane-container'

    parent = @parent().view()
    unless parent.hasClass(axis)
      axis = @buildPaneAxis(axis)
      if parent instanceof PaneContainer
        @detach()
        axis.addChild(this)
        parent.setRoot(axis)
      else
        parent.insertChildBefore(this, axis)
        axis.addChild(this)
      parent = axis

    newPane = new Pane(items...)

    switch side
      when 'before' then parent.insertChildBefore(this, newPane)
      when 'after' then parent.insertChildAfter(this, newPane)
    @getContainer().adjustPaneDimensions()
    newPane.makeActive()
    newPane.focus()
    newPane

  # Private:
  buildPaneAxis: (axis) ->
    switch axis
      when 'row' then new PaneRow()
      when 'column' then new PaneColumn()

  # Private:
  getContainer: ->
    @closest('.panes').view()

  # Private:
  copyActiveItem: ->
    @activeItem.copy?() ? atom.deserializers.deserialize(@activeItem.serialize())

  # Private:
  remove: (selector, keepData) ->
    return super if keepData
    @parent().view().removeChild(this)

  # Private:
  beforeRemove: ->
    if @is(':has(:focus)')
      @getContainer().focusNextPane() or atom.workspaceView?.focus()
    else if @isActive()
      @getContainer().makeNextPaneActive()

    item.destroy?() for item in @getItems()
