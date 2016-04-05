# spc-slack-rsvp
Slack で出欠を記録します。
毎日変わる4桁のキーワードを使います。

## 権限
ユーザーには3種類の権限があります。

| 種類 | 権限 |
|:--|:--|
| USER | 自分が出席していることを主張できる |
| OP | USER の権限 + 出欠確認を開始できる |
| ADMIN | OP の権限 + OP の付与・剥奪ができる |

## USER
OP の誰かにキーワードを伝えられたら、それを DM で bot に送信します。

例えばキーワードが `ACDE` なら
```
ACDE
```
と DM を送ります。

以下のコマンドが使えます。

| コマンド | 意味 |
|:--|:--|
| op.list | OP 一覧を表示する |

## OP
活動を開始する前にDM で bot に `出欠` または `rsvp` 等と送信し、返信されたキーワードを活動に参加する USER 全員に伝えます。

例えば、キーワードをホワイトボードに書く、口頭で言う等の方法があります。その場にいる人だけに伝わるようにしてください。

## ADMIN
以下のコマンドが使えます。

| コマンド | 意味 |
|:--|:--|
| op.add @username | @username に OP 権限を付与する |
| op.remove @username | @username の OP 権限を剥奪する |