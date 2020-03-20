{-# OPTIONS_GHC -Wno-unused-imports #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE FlexibleContexts #-}

module Frontend where

import ClassyPrelude
import Prelude ()
import Control.Monad
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import Language.Javascript.JSaddle (eval, liftJSM)
import Urbit.Atom
import Reflex.Dom.Widget.Input
import Reflex.Host.Class

import Obelisk.Frontend
import Obelisk.Configs
import Obelisk.Route
import Obelisk.Generated.Static

import Reflex.Dom.Core

import Common.Api
import Common.Route

import System.IO.Unsafe    (unsafePerformIO)
import Urbit.Moon.Repl     (evalTextFast, evalText)
import Urbit.Uruk.UrukDemo (Env, EvalResult(..), Inp(..), InpResult(..), Exp)
import Urbit.Uruk.UrukDemo (execInp, execText, parseInps, prettyInpResult)

--------------------------------------------------------------------------------

thinking :: Text
thinking = "Thinking..."

fastResult
  :: ( TriggerEvent t m
     , MonadHold t m
     , Reflex t
     , PerformEvent t m
     , MonadIO (Performable m)
     )
  => Dynamic t Text
  -> m (Dynamic t Text)
fastResult txt = do
  (e, f) <- newTriggerEvent
  performEvent_ $ fmap (compute fastBrain thinking f evalTextFast) $ updated txt
  res <- holdDyn thinking e
  pure res

slowResult
  :: ( TriggerEvent t m
     , MonadHold t m
     , Reflex t
     , PerformEvent t m
     , MonadIO (Performable m)
     )
  => Dynamic t Text
  -> m (Dynamic t Text)
slowResult txt = do
  (e, f) <- newTriggerEvent
  performEvent_ $ fmap (compute slowBrain thinking f evalText) $ updated txt
  res <- holdDyn thinking e
  pure res

urukResult
  :: ( TriggerEvent t m
     , MonadHold t m
     , Reflex t
     , PerformEvent t m
     , MonadIO (Performable m)
     )
  => Dynamic t Text
  -> m (Dynamic t (Either Text [InpResult]))
urukResult txt = do
  (e, f) <- newTriggerEvent
  let think = Left thinking
  performEvent_ $ fmap (compute urukBrain think f (pure . goInp)) $ updated txt
  holdDyn think e
 where
  goInp :: Text -> Either Text [InpResult]
  goInp txt = parseInps txt >>= fmap snd . inpSeq mempty

inpSeq :: Env -> [Inp] -> Either Text (Env, [InpResult])
inpSeq initEnv = go initEnv []
 where
  go env acc []     = pure (env, reverse acc)
  go env acc (x:xs) = do
    (env', r) <- execInp env x
    go env' (r:acc) xs

fastBrain :: MVar (Maybe (Async ()))
fastBrain = unsafePerformIO (newMVar Nothing)

slowBrain :: MVar (Maybe (Async ()))
slowBrain = unsafePerformIO (newMVar Nothing)

urukBrain :: MVar (Maybe (Async ()))
urukBrain = unsafePerformIO (newMVar Nothing)

compute
  :: MonadIO m
  => MVar (Maybe (Async ())) --  thread to kill
  -> b                       --  Value while executing
  -> (b -> IO ())            --  Callback
  -> (a -> IO b)             --  Action
  -> a                       --  Argument
  -> m ()
compute ref thinking cb exec txt = do
  takeMVar ref >>= maybe (pure ()) cancel
  liftIO (cb thinking)
  tid <- liftIO $ async $ (exec txt >>= liftIO . cb)
  putMVar ref (Just tid)

slow
  :: ( Monad m
     , MonadSample s m
     , Reflex s
     , DomBuilder s m
     , PostBuild s m
     , PerformEvent s m
     , MonadHold s m
     , TriggerEvent s m
     , MonadIO (Performable m)
     )
  => m ()
slow = do
  el "h3" (text "Slow")

  val <-
    fmap _inputElement_value
    $  inputElement
    $  (def & inputElementConfig_initialValue .~ "(K K K)")

  res <- slowResult val

  el "pre" (dynText res)

inpInputW :: (Reflex s, DomBuilder s m, Monad m) => InpResult -> m ()
inpInputW res = do
  el "h4" (text "Input")
  case res of
    InpWipe v     -> el "pre" (text ("!" <> v))
    InpExpr e _   -> el "pre" (text $ tshow e)
    InpDecl v e _ -> el "pre" (text $ "=" <> v <> " " <> tshow e)

showExp :: (Monad m, Reflex t, DomBuilder t m) => Exp -> m ()
showExp = el "pre" . text . tshow

showDecl :: (Monad m, Reflex t, DomBuilder t m) => Text -> Exp -> m ()
showDecl nm exp = do
  el "pre" (text ("=" <> nm <> " " <> tshow exp))

inpResultEvalResult :: InpResult -> Maybe EvalResult
inpResultEvalResult = \case
  InpWipe _     -> Nothing
  InpExpr _ r   -> pure r
  InpDecl _ _ r -> pure r

inpResultW :: (Reflex s, DomBuilder s m, Monad m) => InpResult -> m ()
inpResultW = \case
  InpWipe _                    -> pure ()
  InpExpr _ (EvalResult x _)   -> hdr >> showExp x
  InpDecl v _ (EvalResult x _) -> hdr >> showDecl v x
 where
  hdr = el "h4" (text "Result")

showTrace :: (Monad m, Reflex t, DomBuilder t m) => [Exp] -> m ()
showTrace = traverse_ showExp

showDeclTrace :: (Monad m, Reflex t, DomBuilder t m) => Text -> [Exp] -> m ()
showDeclTrace v = traverse_ (showDecl v)

inpTraceW :: (Reflex s, DomBuilder s m, Monad m) => InpResult -> m ()
inpTraceW = \case
  InpWipe _                    -> pure ()
  InpExpr _ (EvalResult _ t)   -> hdr >> showTrace (reverse t)
  InpDecl v _ (EvalResult _ t) -> hdr >> showDeclTrace v (reverse t)
 where
  hdr = el "h4"  (text "Reductions")

resultPreview
  :: ( Monad m
     , Reflex t
     , DomBuilder t m
     , MonadSample t m
     , MonadHold t m
     , PostBuild t m
     )
  => Either Text [InpResult]
  -> m ()
resultPreview eRes = do
  case eRes of
    Left  err     -> el "pre" (text err)
    Right results -> do
      for_ results $ \case
        InpWipe _                    -> pure ()
        InpExpr _ (EvalResult x _)   -> showExp x
        InpDecl _ _ (EvalResult x _) -> showExp x

prettyInpResultW
  :: ( Monad m
     , Reflex t
     , DomBuilder t m
     , MonadSample t m
     , MonadHold t m
     , PostBuild t m
     )
  => Either Text [InpResult]
  -> m ()
prettyInpResultW res = do
  el "h3" (text "Execution Results")
  case res of
    Left  err     -> el "pre" (text err)
    Right results -> do
      for_ results $ \res -> do
        inpInputW res
        inpResultW res
        inpTraceW res

prettyInpWaiting :: (Monad m, Reflex t, DomBuilder t m) => m ()
prettyInpWaiting = do
  el "h3" (text "Execution Results")
  el "pre" (text "Waiting for input")

urukW
  :: ( Monad m
     , MonadSample s m
     , Reflex s
     , DomBuilder s m
     , PostBuild s m
     , PerformEvent s m
     , MonadHold s m
     , TriggerEvent s m
     , MonadIO (Performable m)
     )
  => m ()
urukW = do
  el "h2" (text "Demo")

  val <-
    fmap _inputElement_value
    $  inputElement
    $  (def & inputElementConfig_initialValue .~ "(K K K)")

  resD <- urukResult val

  el "h3" (text "Preview")

  void $ widgetHold (pure ()) (resultPreview <$> updated resD)

  press   <- button "Execute"

  let execRes = current resD <@ press

  void $ widgetHold prettyInpWaiting (prettyInpResultW <$> execRes)

fast
  :: ( Monad m
     , MonadSample s m
     , Reflex s
     , DomBuilder s m
     , PostBuild s m
     , PerformEvent s m
     , MonadHold s m
     , TriggerEvent s m
     , MonadIO (Performable m)
     )
  => m ()
fast = do
  el "h3" (text "Fast")

  val <-
    fmap _inputElement_value
    $  inputElement
    $  (def & inputElementConfig_initialValue .~ "(K K K)")

  res <- fastResult val

  el "pre" $ dynText res


-- This runs in a monad that can be run on the client or the server.
-- To run code in a pure client or pure server context, use one of the
-- `prerender` functions.
frontend :: Frontend (R FrontendRoute)
frontend = Frontend
  { _frontend_head = do
                       el "title" $ text "Uruk Demo"
                       elAttr
                         "link"
                         (  "href"
                         =: static @"main.css"
                         <> "type"
                         =: "text/css"
                         <> "rel"
                         =: "stylesheet"
                         )
                         blank
  , _frontend_body = do

    el "h1" $ do
      text "Uruk"

    el "h3" $ do
      text "Quick Reference"

    el "pre" $ do
      text $ unlines
        [ "Command Syntax:"
        , "    EXPR     ::  Evaluate EXPR"
        , "    =x EXPR  ::  Bind `x` to result of evaluating EXPR"
        , "    !x       ::  Unbind `x`"
        , "    !x       ::  Unbind `x`"
        , ""
        , "Syntax:"
        , "    /[SKJD]/           ->  primtive combinators S, K, J, D"
        , "    /[$a-z]+/          ->  identifier (reference to bound variable)"
        , "    (x:EXPR y:EXPR)    ->  Call `x` with argument `y`."
        , "    (x y z)            ->  ((x y) z)"
        , "    (x y z ...)        ->  ((x y) z ...)"
        , ""
        , "Reduction Rules:"
        , "    *(K x y)           -> x"
        , "    *(x y)             -> (*x y)"
        , "    *(x y)             -> (x *y)"
        , "    *(S x y z)         -> (x z (y z))"
        , "    *(D x)             -> JAM(x)"
        , "    *(J^n t f x1 … xn) -> (f x1 … xn)"
        , ""
        , "Examples:"
        , "    =id (J K S K K)"
        , ""
        , "    =rawzer (S K)"
        , "    =rawsuc (S (S (K S) K))"
        , "    =rawone (rawsuc rawzer)"
        , "    =rawtwo (rawsuc rawone)"
        , "    =rawthr (rawsuc rawtwo)"
        , "    =rawfor (rawsuc rawthr)"
        , ""
        , "    =pak (J K (S (K (J J K)) (S (S id (K rawsuc)) (K rawzer))))"
        , "    =inc (J K (S (K pak) (S (S (K S) K))))"
        , "    =add (J J K (S (K (S (K pak))) (S (K S) (S (K (S (K S) K))))))"
        , "    =zer (pak rawzer)"
        , "    =one (inc zer)"
        , ""
        , "    =cons (J J J K (S (K (S (K (S (K (S (K (S S (K K))) K)) S)) (S id))) K))"
        , "    =car (J K (S id (K K)))"
        , "    =cdr (J K (S id (K (S K))))"
        , ""
        , "    (car (cons zer (id (inc (inc (inc (zer)))))))"
        ]

    urukW

    el "hr" $ pure ()
    el "hr" $ pure ()
    el "hr" $ pure ()
    el "hr" $ pure ()
    el "hr" $ pure ()

    el "h2" $ text "Old Stuff"

    fast

    slow

    return ()
  }
