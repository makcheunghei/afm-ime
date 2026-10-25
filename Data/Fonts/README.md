# 候選字型後備

`HanaMinB.ttf` 是未修改的 Hanazono Mincho B（2017-09-04），用於系統字型無法顯示的補充平面漢字。僅在 AFM 程序內登記，不安裝到系統字型目錄。一般字仍優先使用 macOS 原有字型。

- 原作者：[GlyphWiki Project / Hanazono fonts](https://glyphwiki.org/hanazono/)
- 本次下載：[Debian 原始發行封存](https://deb.debian.org/debian/pool/main/f/fonts-hanazono/fonts-hanazono_20170904.orig.tar.bz2)
- 封存 SHA-256：`b1a342c74d07c54b27d861c826f33014192bcccfa675c68f7eb926d316dbe020`，對照 [Debian source descriptor](https://deb.debian.org/debian/pool/main/f/fonts-hanazono/fonts-hanazono_20170904-3.dsc)。
- 字型 SHA-256：`829543436cdf7b4c6730e2af5806fa406f8ddf0d4b656e0cd49c58d4db1c8d3c`
- 原始雙重授權及版權全文：`LICENSE.txt`，隨 App 一起分發。

更新字型時須同時核對來源、授權、打包校驗碼及完整速成詞庫的字形覆蓋。不得以 glyph ID 非零當作有字形：CoreText 的 `LastResort` 亦會回傳非零佔位 glyph。
