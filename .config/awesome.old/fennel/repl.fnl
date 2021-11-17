;; This module is the read/eval/print loop; for coding Fennel interactively.

;; The most complex thing it does is locals-saving, which allows locals to be
;; preserved in between "chunks"; by default Lua throws away all locals after
;; evaluating each piece of input.

(local utils (require :fennel.utils))
(local parser (require :fennel.parser))
(local compiler (require :fennel.compiler))
(local specials (require :fennel.specials))

(fn default-read-chunk [parser-state]
  (io.write (if (< 0 parser-state.stack-size) ".." ">> "))
  (io.flush)
  (let [input (io.read)]
    (and input (.. input "\n"))))

(fn default-on-values [xs]
  (io.write (table.concat xs "\t"))
  (io.write "\n"))

(fn default-on-error [errtype err lua-source]
  (io.write
   (match errtype
     "Lua Compile" (.. "Bad code generated - likely a bug with the compiler:\n"
                       "--- Generated Lua Start ---\n"
                       lua-source
                       "--- Generated Lua End ---\n")
     "Runtime" (.. (compiler.traceback err 4) "\n")
     _ (: "%s error: %s\n" :format errtype (tostring err)))))

(local save-source
       (table.concat ["local ___i___ = 1"
                      "while true do"
                      " local name, value = debug.getlocal(1, ___i___)"
                      " if(name and name ~= \"___i___\") then"
                      " ___replLocals___[name] = value"
                      " ___i___ = ___i___ + 1"
                      " else break end end"] "\n"))

(fn splice-save-locals [env lua-source]
  (set env.___replLocals___ (or env.___replLocals___ {}))
  (let [spliced-source []
        bind "local %s = ___replLocals___['%s']"]
    (each [line (lua-source:gmatch "([^\n]+)\n?")]
      (table.insert spliced-source line))
    (each [name (pairs env.___replLocals___)]
      (table.insert spliced-source 1 (bind:format name name)))
    (when (and (< 1 (# spliced-source))
               (: (. spliced-source (# spliced-source)) :match "^ *return .*$"))
      (table.insert spliced-source (# spliced-source) save-source))
    (table.concat spliced-source "\n")))

(local commands {})

(fn command? [input] (input:match "^%s*,"))

(fn commands.help [_ _ on-values]
  (on-values ["Welcome to Fennel.
This is the REPL where you can enter code to be evaluated.
You can also run these repl commands:

  ,help - show this message
  ,reload module-name - reload the specified module
  ,reset - erase all repl-local scope
  ,exit - leave the repl

Use (doc something) to see descriptions for individual macros and special forms.

For more information about the language, see https://fennel-lang.org/reference"]))

(fn reload [module-name env on-values on-error]
  ;; Sandbox the reload inside the limited environment, if present.
  (match (pcall (specials.load-code "return require(...)" env) module-name)
    (true old) (let [_ (tset package.loaded module-name nil)
                     (ok new) (pcall require module-name)
                     ;; keep the old module if reload failed
                     new (if (not ok) (do (on-values new) old) new)]
                 ;; if the module isn't a table then we can't make changes
                 ;; which affect already-loaded code, but if it is then we
                 ;; should splice new values into the existing table and
                 ;; remove values that are gone.
                 (when (and (= (type old) :table) (= (type new) :table))
                   (each [k v (pairs new)]
                     (tset old k v))
                   (each [k (pairs old)]
                     (when (= nil (. new k))
                       (tset old k nil)))
                   (tset package.loaded module-name old))
                 (on-values [:ok]))
    (false msg) (on-error "Runtime" (pick-values 1 (msg:gsub "\n.*" "")))))

(fn commands.reload [read env on-values on-error]
  (match (pcall read)
    (true true module-sym) (reload (tostring module-sym) env on-values on-error)
    (false ?parse-ok ?msg) (on-error "Parse" (or ?msg ?parse-ok))))

(fn commands.reset [_ env on-values]
  (set env.___replLocals___ {})
  (on-values [:ok]))

(fn run-command [input read loop env on-values on-error]
  (let [command-name (input:match ",([^%s/]+)")]
    (match (. commands command-name)
      command (command read env on-values on-error)
      _ (when (not= "exit" command-name)
          (on-values ["Unknown command" command-name])))
    (when (not= "exit" command-name)
      (loop))))

(fn completer [env scope text]
  (let [matches []
        input-fragment (text:gsub ".*[%s)(]+" "")]
    (fn add-partials [input tbl prefix] ; add partial key matches in tbl
      (each [k (utils.allpairs tbl)]
        (let [k (if (or (= tbl env) (= tbl env.___replLocals___))
                    (. scope.unmanglings k)
                    k)]
          (when (and (< (# matches) 2000) ; stop explosion on too many items
                     (= (type k) "string")
                     (= input (k:sub 0 (# input))))
            (table.insert matches (.. prefix k))))))
    (fn add-matches [input tbl prefix] ; add matches, descending into tbl fields
      (let [prefix (if prefix (.. prefix ".") "")]
        (if (not (input:find "%.")) ; no more dots, so add matches
            (add-partials input tbl prefix)
            (let [(head tail) (input:match "^([^.]+)%.(.*)")
                  raw-head (if (or (= tbl env) (= tbl env.___replLocals___))
                               (. scope.manglings head)
                               head)]
              (when (= (type (. tbl raw-head)) "table")
                (add-matches tail (. tbl raw-head) (.. prefix head)))))))

    (add-matches input-fragment (or scope.specials []))
    (add-matches input-fragment (or scope.macros []))
    (add-matches input-fragment (or env.___replLocals___ []))
    (add-matches input-fragment env)
    (add-matches input-fragment (or env._ENV env._G []))
    matches))

(fn repl [options]
  (let [old-root-options utils.root.options
        env (if options.env
                (specials.wrap-env options.env)
                (setmetatable {} {:__index (or _G._ENV _G)}))
        save-locals? (and (not= options.saveLocals false)
                          env.debug env.debug.getlocal)
        opts {}
        _ (each [k v (pairs options)] (tset opts k v))
        read-chunk (or opts.readChunk default-read-chunk)
        on-values (or opts.onValues default-on-values)
        on-error (or opts.onError default-on-error)
        pp (or opts.pp tostring)
        ;; make parser
        (byte-stream clear-stream) (parser.granulate read-chunk)
        chars []
        (read reset) (parser.parser (fn [parser-state]
                                      (let [c (byte-stream parser-state)]
                                        (table.insert chars c)
                                        c)))
        scope (compiler.make-scope)]

    ;; use metadata unless we've specifically disabled it
    (set opts.useMetadata (not= options.useMetadata false))
    (when (= opts.allowedGlobals nil)
      (set opts.allowedGlobals (specials.current-global-names opts.env)))

    (when opts.registerCompleter
      (opts.registerCompleter (partial completer env scope)))

    (fn print-values [...]
      (let [vals [...]
            out []]
        (set (env._ env.__) (values (. vals 1) vals))
        ;; utils.map won't work here because of sparse tables
        (for [i 1 (select :# ...)]
          (table.insert out (pp (. vals i))))
        (on-values out)))

    (fn loop []
      (each [k (pairs chars)] (tset chars k nil))
      (let [(ok parse-ok? x) (pcall read)
            src-string (string.char ((or _G.unpack table.unpack) chars))]
        (set utils.root.options opts)
        (if (not ok)
            (do (on-error "Parse" parse-ok?)
                (clear-stream)
                (reset)
                (loop))
            (command? src-string) (run-command src-string read loop env
                                               on-values on-error)
            (when parse-ok? ; if this is false, we got eof
              (match (pcall compiler.compile x {:correlate opts.correlate
                                                :source src-string
                                                :scope scope
                                                :useMetadata opts.useMetadata
                                                :moduleName opts.moduleName
                                                :assert-compile opts.assert-compile
                                                :parse-error opts.parse-error})
                (false msg) (do (clear-stream)
                                (on-error "Compile" msg))
                (true src) (let [src (if save-locals?
                                         (splice-save-locals env src)
                                         src)]
                             (match (pcall specials.load-code src env)
                               (false msg) (do (clear-stream)
                                               (on-error "Lua Compile" msg src))
                               (_ chunk) (xpcall #(print-values (chunk))
                                                 (partial on-error "Runtime")))))
              (set utils.root.options old-root-options)
              (loop)))))
    (loop)))