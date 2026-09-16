# 鈴聲素材與授權紀錄

## 以程式產生的 7 個鈴聲

`silver-bell.wav`、`crystal.wav`、`breeze.wav`、`sunrise.wav`、`moonlight.wav`、
`beacon.wav`、`sparkle.wav`

這些檔案由本專案的 `tools/generate_ringtones.py` 以數學波形從零產生。產生過程不含第三方錄音、取樣、MIDI、旋律檔或其他外部素材，可由同一腳本確定性重建。

授權識別碼：`CC0-1.0`。專案擁有者將上述 7 個音訊檔與產生腳本依 [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/legalcode) 提供，可不受限制地用於本 App 的商業發行、修改與再散布，不要求署名或支付權利金；若當地法律不允許放棄所有權利，則適用 CC0 的備援授權條款。

> 注意：「免權利金」不等於「沒有著作權」。本批素材的上架風險較低，是因為它們沒有引用第三方素材，且保留了完整、可重建的產生來源。

## 原有的 9 個鈴聲

`chime.wav`、`marimba.wav`、`ping.wav`、`rise.wav`、`fall.wav`、`double.wav`、
`triple.wav`、`alert.wav`、`soft.wav` 在既有程式碼中記載為本專案自行合成的原創音效。這批沒有可重跑的產生腳本，因此只做修補、不重新產生，音色維持原樣。

## 爆音修補（`tools/declick_ringtones.py`）

原本每顆鈴聲都聽得到「喀、喀」的雜音，來源是波形的瞬間斷點：

- `triple`、`double`、`alert` 的嗶聲是硬切的——波形從數位靜音直接跳到滿幅、再從滿幅直接歸零。例如 `triple` 在 0.16 秒是在振幅 −4382（−17.5 dBFS）被切斷，下一聲又從 −9036 開始。每個斷點都會輻射出寬頻的喀聲。
- `chime`、`soft` 的檔案在聲音還在響（約 −35 dBFS）的時候就結束了。
- `ping`、`marimba`、`rise`、`fall` 的結尾沒有收乾淨。因為連響功能會把同一個檔案接 2～5 次，這個斷點在每一次接縫都會再響一遍。

修補方式是找出這些斷點，套上短的升餘弦斜坡（起音 3 毫秒、收音 8 毫秒），並確保每個檔案結尾都有 30 毫秒的真正靜音，接縫才會安靜。斜坡以外的取樣原封不動地複製，所以鈴聲的個性不變。這個工具可重複執行：已經平滑的檔案會被判定為 `clean` 並原樣寫回。

判斷依據是「斷點前的音量有沒有真的在衰減」：硬切的嗶聲在停止的瞬間仍保有視窗峰值的 0.94～0.98，而正常收音的音符早已掉到 0.31，兩者分得很開。

## 移除的鈴聲

`urgent.wav`（急促 / Urgent）已從清單與專案中刪除。舊版若有使用者選過它，`SoundCatalog.resolved(id:)` 會自動退回預設的「鐘聲」。

## 音量一致性

`generate_ringtones.py` 舊版的正規化寫成 `min(0.88 / peak, 1.0)`，那個 `1.0` 上限會讓本來就不夠大聲的鈴聲維持原樣，結果 `sparkle`、`breeze` 等比其他鈴聲小了 4～5 dB。現在全部統一正規化到與原有 9 顆相同的峰值（27524 / 32767），清單裡不會有某顆特別小聲。

## 技術規格

- 格式：WAV / Linear PCM
- 取樣率：44,100 Hz
- 位元深度：16-bit（量化時加入固定種子的 TPDF dither，長衰減尾巴才不會變得顆粒狀）
- 聲道：單聲道
- 單次長度：全部少於 2.3 秒；即使 App 設定重複 5 次也少於 iOS 自訂通知音效的 30 秒限制

## 重新產生

```bash
python3 tools/generate_ringtones.py   # 重建以程式產生的 7 顆
python3 tools/declick_ringtones.py    # 對 Sounds/ 全部做一次爆音修補
```

## 連響快取

連響（2～5 次）沒辦法靠 `UNNotificationSound` 設定，所以 App 會在 `Library/Sounds` 產生一份接好的音檔，依「鈴聲 × 次數 × 版本」命名。

若日後再次替換鈴聲原始檔，記得同時提高 `SoundCatalog.repeatedNotificationSoundName` 裡的快取版本號（目前是 `v2`），否則已安裝的裝置會繼續沿用舊的連響檔。

舊檔不必手動處理：`SoundCatalog.pruneRepeatCache(keeping:)` 會在待送通知每次重排完成之後，把當下沒被引用到的連響檔全部刪掉——換版本、下架鈴聲、使用者改連響次數留下的殘檔都包含在內。它比對的是「現在真的被引用的檔名」而不是版本字串，所以日後換鈴聲不需要再同步改清理規則。

清理的時機很重要：一定要等 `synchronizePending` 完成待送通知同步後才能刪。提早刪會把仍被既有通知引用的檔案清掉，那些通知就會改響系統預設音。
