import XMonad
import XMonad.Hooks.DynamicLog
import XMonad.Hooks.ManageDocks
import XMonad.Util.Run(spawnPipe)
import XMonad.Util.EZConfig(additionalKeys)
import System.IO

main = do
    xmproc <- spawnPipe "/usr/bin/xmobar /home/thomas/.xmobarrc"

    xmonad $ docks $ defaultConfig
        { manageHook = manageDocks <+> manageHook defaultConfig
        , layoutHook = avoidStruts  $  layoutHook defaultConfig
        , logHook = dynamicLogWithPP xmobarPP
                        { ppOutput = hPutStrLn xmproc
                        , ppTitle = xmobarColor "green" "" . shorten 50
                        }
        , modMask = mod4Mask     -- Rebind Mod to the Windows key
        } `additionalKeys`
        [ ((controlMask, xK_Print), spawn "sleep 0.2; scrot -s")
        , ((controlMask .|. mod1Mask, xK_Delete), spawn "xset dpms 0 0 2; xset dpms force off; slock && xset dpms 0 0 60")
        , ((0, xK_Print), spawn "scrot")
        , ((0, 0x1008FF11), spawn "amixer -c 1 -q sset Master 2%-")
        , ((0, 0x1008FF13), spawn "amixer -c 1 -q sset Master 2%+")
        , ((0, 0x1008FF12), spawn "amixer -D pulse set Master 1+ toggle")
        ]
