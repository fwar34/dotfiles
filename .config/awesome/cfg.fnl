(local fun (require "fun"))
(local gears (require "gears"))
(local awful (require "awful"))
(require "awful.autofocus")
(local naughty (require "naughty"))
(require-macros "macros")

(local focus-colors 
  ; from https://colorhunt.co/palette/153787
  ; ["#eb7070" "#fec771" "#e6e56c" "#64e291" ]
  ; from https://colorhunt.co/palette/136945 
  ["#cd4545" "#f16821" "#f3a333" "#fffe9a"]
  )

(local unfocus-color "#000000")

(local focus-border-width 1)

(local background-color "#102")

; Tools

(fn notify
  [text]
  (naughty.notify {:text text}))

(fn debug
  [x]
  (notify (gears.debug.dump_return x)))

(fn cset
  [k v]
  (fn [c]
    (tset c k v)))

(fn cinv
  [k]
  (fn [c]
    (let [v (. c k)]
      (tset c k (not v)))))

(local modifiers {:mod "Mod4"
                  :shift "Shift"
                  :ctrl "Control"})

(fn map-mods
  [mods]
  (->> mods 
       (fun.map (partial . modifiers))
       (fun.totable)))

(fn key
  [mods key-code fun]
  (awful.key (map-mods mods) key-code fun))

(fn btn
  [mods btn-code fun]
  (awful.button (map-mods mods) btn-code fun))

(fn invert-screen
  [invert?]
  (os.execute "xcalib -c -a") ; clear
  (when invert?
    (os.execute "xcalib -i -a")))

; Tag managment

(local layouts [
                awful.layout.suit.fair
                awful.layout.suit.tile
                awful.layout.suit.max.fullscreen])

(local tags {})

(var current-tag-pos [0 0])

(fn set-tag-pos
  [tag pos]
  (let [[x y] pos]
    (->> {"x-pos" x "y-pos" y}   
         (fun.each (partial awful.tag.setproperty tag)))))

(fn get-tag-pos
  [tag]
  (->> ["x-pos" "y-pos"]
       (fun.map (partial awful.tag.getproperty tag))
       (fun.totable)))

(fn translate-pos
  [pos off]
  (let [[x y] pos
        [off-x off-y] off]
    [(+ x off-x) (+ y off-y)]))

(fn tag-name
  [pos]
  (let [[x y] pos ]
    (.. "(" x " " y ")")))

(fn get-or-create-tag
  [pos]
  (let [tn (tag-name pos)]
    (when (not (. tags tn))
      (let [[tag] (awful.tag [tn] mouse.screen (. layouts 1))]
        (tset tags tn tag)
        (set-tag-pos tag pos)))
    (. tags tn)))

(fn current-tag
  []
  (get-or-create-tag current-tag-pos))

(fn view-current-tag
  []
  (: (current-tag) :view_only))

(fn view-all-tags
  []
  (let [ts (. mouse.screen :tags)]
    (each [_ t (pairs ts)]
      (tset t :selected true))))

(fn select-tag-by-focused-client
  [c]
  (let [tags (c:tags)]
    (when (# tags)
      (let [[tag] tags]
        (set current-tag-pos (get-tag-pos tag))
        (view-current-tag)))))

(fn select-current-tag-by-offset
  [off]
  (with-selected-tag tag
    (set current-tag-pos (get-tag-pos tag)))
  (set current-tag-pos (translate-pos current-tag-pos off))
  (view-current-tag))

(fn move-client-relative
  [off c]
  (c:move_to_tag (get-or-create-tag (translate-pos current-tag-pos off))))

(fn move-client-relative-and-select
  [off c]
  (move-client-relative off c)
  (select-current-tag-by-offset off))

(fn move-all-clients-relative-and-select
  [off]
  (fun.each (partial move-client-relative off)
            (awful.client.visible))
  (select-current-tag-by-offset off))

(fn focus-client-by-offset
  [off]
  (awful.client.focus.byidx off)
  (when client.focus
    (client.focus:raise)))

(local inverted-prop "inverted")

(fn is-inverted?
  [t]
  (if (awful.tag.getproperty t inverted-prop) true false))

(fn set-inverted
  [t inverted?]
  (awful.tag.setproperty t inverted-prop inverted?)
  (invert-screen inverted?))

(fn toggle-invert-screen
  []
  (with-selected-tag t
    (let [inverted? (not (is-inverted? t))]
      (set-inverted t inverted?))))

(fn arrange-tag 
  [screen]
  ; focus from history
  (when (not client.focus)
    (let [c (awful.client.focus.history.get screen 0)]
      (when c
        (tset client :focus c))))
  ; set a border width, if there is more than one client on the tag
  (let [cs (awful.client.visible screen)
        bw (if (> (# cs) 1) focus-border-width 0)]
    (fun.each 
      (fn [c focus-color]
        (doto c
              (tset :border_width bw)
              (tset :focus_color focus-color)))
      (fun.zip cs (fun.cycle focus-colors))))
  ; set focus color for current client (focus event is before arrange and the colors are not there yet)
  (let [c (. client :focus)]
    (when c
      (tset c :border_color (. c :focus_color))))
  ; set inverted screen state from tag
  (with-selected-tag t
    (invert-screen (is-inverted? t))))

(fn unminimize-tag
  [tag]
  (fun.each (fn [client]
              (tset client :minimized false)
              (client:redraw))
            (tag:clients)))

;;; Main Config

(local global-keys
       (gears.table.join
         (key [:mod :shift :ctrl] "Escape"    awesome.restart)
         (key [:mod :shift]       "a"         view-all-tags)
         (key [:mod :shift]       "i"         toggle-invert-screen)
         (key [:mod]              "h"         #(select-current-tag-by-offset [-1  0]))
         (key [:mod]              "l"         #(select-current-tag-by-offset [ 1  0]))
         (key [:mod]              "k"         #(select-current-tag-by-offset [ 0 -1]))
         (key [:mod]              "j"         #(select-current-tag-by-offset [ 0  1]))
         (key [:mod :ctrl]        "h"         #(move-all-clients-relative-and-select [-1  0]))
         (key [:mod :ctrl]        "l"         #(move-all-clients-relative-and-select [ 1  0]))
         (key [:mod :ctrl]        "k"         #(move-all-clients-relative-and-select [ 0 -1]))
         (key [:mod :ctrl]        "j"         #(move-all-clients-relative-and-select [ 0  1]))
         (key [:mod]              "space"     #(awful.layout.inc layouts  1))
         (key [:mod :shift]       "space"     #(awful.layout.inc layouts -1))
         (key [:mod :ctrl]        "space"     awful.client.floating.toggle)
         (key [:mod]              "Tab"       #(focus-client-by-offset  1))
         (key [:mod :shift]       "Tab"       #(focus-client-by-offset -1))
         (key [:mod :ctrl]        "Tab"       #(awful.client.swap.byidx  1))
         (key [:mod :shift :ctrl] "Tab"       #(awful.client.swap.byidx -1))
         (key [:mod :shift]       "BackSpace" #(unminimize-tag (awful.tag.selected)))
         ))

(local client-keys
       (gears.table.join
         (key [:mod]        "Escape" (fn [c] (c:kill)))
         (key [:mod]        "a"      select-tag-by-focused-client)
         (key [:mod :shift] "f"      (cinv :focusable))
         (key [:mod :shift] "s"      (cinv :sticky))
         (key [:mod :shift] "x"      (cinv :maximized_horizontal))
         (key [:mod :shift] "y"      (cinv :maximized_vertical))
         (key [:mod :shift] "m"      (cinv :maximized))
         (key [:mod :shift] "h"      (partial move-client-relative-and-select [-1  0]))
         (key [:mod :shift] "l"      (partial move-client-relative-and-select [ 1  0]))
         (key [:mod :shift] "k"      (partial move-client-relative-and-select [ 0 -1]))
         (key [:mod :shift] "j"      (partial move-client-relative-and-select [ 0  1]))
         ))

(local client-buttons
       (awful.util.table.join
         (btn [:mod] 1 awful.mouse.client.move)
         (btn [:mod] 3 awful.mouse.client.resize)
         ))

(local rules [
              {:rule {}
               :properties {:focus true
                            :keys client-keys
                            :buttons client-buttons}}
              ])

(local client-event-handlers 
  {"manage"       (fn [c] 
                    (c:move_to_tag (current-tag)))
   "mouse::enter" (fn [c]
                    ; TODO if awful.layout.get(c.screen) ~= awful.layout.suit.magnifier and awful.client.focus.filter(c) then
                    (if (awful.client.focus.filter c)
                      (tset client :focus c)))
   "focus"        (fn [c] 
                    (let [focus-color (. c :focus_color)] 
                      ; focus (e.g. from rules) is applied before arrange and the client might not yet have a color
                      (when focus-color
                        (tset c :border_color focus-color))))
   "unfocus"      (cset :border_color unfocus-color)})

; Wire everything up

(fun.each client.connect_signal client-event-handlers)

(awful.screen.connect_for_each_screen
  (fn [s] 
    (s:connect_signal "arrange" arrange-tag)))

(root.keys global-keys)

(tset awful.rules :rules rules)

(view-current-tag)

(gears.wallpaper.set background-color)

{}

