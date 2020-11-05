::  hark-chat-hook: notifications for chat-store [landscape]
::
/-  store=hark-store, post, group-store, metadata-store, hook=hark-chat-hook
/+  resource, metadata, default-agent, dbug, chat-store
::
~%  %hark-chat-hook-top  ..is  ~
|%
+$  card  card:agent:gall
+$  versioned-state
  $%  state-0
  ==
::
+$  state-0
  $:  %0
      watching=(set path)
  ==
::
--
::
=|  state-0
=*  state  -
::
=<
%-  agent:dbug
^-  agent:gall
~%  %hark-chat-hook-agent  ..card  ~
|_  =bowl:gall
+*  this  .
    ha    ~(. +> bowl)
    def   ~(. (default-agent this %|) bowl)
    met   ~(. metadata bowl)
::
++  on-init
  :_  this
  ~[watch-chat:ha]
::
++  on-save  !>(state)
++  on-load
  |=  old=vase
  ^-  (quip card _this)
  `this(state !<(state-0 old))
::
++  on-watch  
  |=  =path
  ^-  (quip card _this)
  =^  cards  state
    ?+    path  (on-watch:def path)
      ::
        [%updates ~]  
      :_  state
      %+  give:ha  ~
      :*  %initial
          watching
      ==
    ==
  [cards this]
::
++  on-poke
  ~/  %hark-chat-hook-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  |^
  ?>  (team:title our.bowl src.bowl)
  =^  cards  state
    ?+  mark           (on-poke:def mark vase)
        %hark-chat-hook-action
      (hark-chat-hook-action !<(action:hook vase))
    ==
  [cards this]
  ::
  ++  hark-chat-hook-action
    |=  =action:hook
    ^-  (quip card _state)
    |^
    ?-  -.action
      %listen  (listen +.action)
      %ignore  (ignore +.action)
    ==
    ++  listen
      |=  chat=path
      ^-  (quip card _state)
      :-  (give:ha ~[/updates] [%listen chat])
      state(watching (~(put in watching) chat))
    ::
    ++  ignore
      |=  chat=path
      ^-  (quip card _state)
      :-  (give:ha ~[/updates] [%ignore chat])
      state(watching (~(del in watching) chat))
    --
  --
::
++  on-agent
  ~/  %hark-chat-hook-agent
  |=  [=wire =sign:agent:gall]
  ^-  (quip card _this)
  |^
  ?+  -.sign  (on-agent:def wire sign)
      %kick
    :_  this
    ?.  ?=([%chat ~] wire)
      ~
    ~[watch-chat:ha]
  ::
      %fact
    ?.  ?=(%chat-update p.cage.sign)
      (on-agent:def wire sign)
    =^  cards  state
      (chat-update !<(update:chat-store q.cage.sign))
    [cards this]
  ==
  ::
  ++  chat-update
    |=  =update:chat-store
    ^-  (quip card _state)
    [~ state]
  --
::
++  on-peek  on-peek:def
::
++  on-leave  on-leave:def
++  on-arvo  on-arvo:def
++  on-fail   on-fail:def
--
|_  =bowl:gall
::
++  give
  |=  [paths=(list path) =update:hook]
  ^-  (list card)
  [%give %fact paths hark-chat-hook-update+!>(update)]~
::
++  watch-chat
  ^-  card
  [%pass /chat %agent [our.bowl %graph-store] %watch /updates]
--