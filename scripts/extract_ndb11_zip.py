#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
extract_ndb11_zip.py
====================
第11回(FY2024)以降のNDBオープンデータ「医科診療行為(算定回数)」ZIPから、
本プロジェクトが使用する 3指標 × 3集計軸 = 9ファイルを取り出し、
従来の命名規則(ndbNN_<section>_<fy>.xlsx)で rawdata_dl 配下へ配置する。

背景:
  第10回までは集計軸ごとに個別xlsx直リンクが公開されていたが、第11回から
  「医科診療行為(算定回数)」が1つのZIPに一括化された。ZIP内のファイル名は
  Shift-JIS(cp932)で格納されており、UTF-8ネイティブのR(Windows/R>=4.2)の
  unzip()では文字化けして正しく取り出せない。本スクリプトはcp932を明示的に
  デコードして確実に取り出す。標準ライブラリのみ使用(zipfile, os, shutil, sys)。

使い方:
  python extract_ndb11_zip.py <zip_path> <rawdata_dl_dir> [edition] [fy]
    zip_path        : ダウンロード済みZIP(公費レセプトを含まないデータ 推奨)
    rawdata_dl_dir  : プロジェクトの rawdata_dl ディレクトリ
    edition         : 回次 (省略時 11)
    fy              : 対象年度(西暦) (省略時 2024)

出力(edition=11, fy=2024 の例):
  rawdata_dl/ndb_pref/M_radiation_pref/ndb11_M_radiation_pref_2024.xlsx
  rawdata_dl/ndb_pref/M_radiation_sexage/ndb11_M_radiation_sexage_2024.xlsx
  rawdata_dl/ndb_sma/M_radiation_sma/ndb11_M_radiation_sma_2024.xlsx
  ...(K手術, D検査 も同様)
"""
import os
import sys
import zipfile

# (section_key, prefix, 親ディレクトリ種別, ZIP内フォルダ判定キーワード, 除外キーワード)
MEASURES = [
    ("M_radiation", "放射線治療", None),
    ("K_surgery",   "手術",       "輸血"),   # K_手術 と K_輸血料 を区別
    ("D_exam",      "検査",       None),
]
# (axis_key, prefix種別, ZIP内ファイル名判定キーワード, 配置先サブツリー)
AXES = [
    ("pref",   "都道府県別", "ndb_pref"),
    ("sexage", "性年齢別",   "ndb_pref"),
    ("sma",    "二次医療圏別", "ndb_sma"),
]
EXCLUDE_AXIS = "診療月別"  # 取得対象外


def decode_name(info):
    """ZIPエントリ名をcp932として復元する。"""
    name = info.filename
    # UTF-8フラグ(bit11)が立っていればそのまま、立っていなければcp437解釈をcp932へ戻す
    if info.flag_bits & 0x800:
        return name
    try:
        return name.encode("cp437").decode("cp932")
    except (UnicodeEncodeError, UnicodeDecodeError):
        try:
            return name.encode("cp437").decode("cp932", errors="replace")
        except Exception:
            return name


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    zip_path = sys.argv[1]
    rawdata_dl = sys.argv[2]
    edition = int(sys.argv[3]) if len(sys.argv) > 3 else 11
    fy = int(sys.argv[4]) if len(sys.argv) > 4 else 2024

    if not os.path.isfile(zip_path):
        print(f"ERROR: ZIPが見つかりません: {zip_path}")
        sys.exit(1)

    zf = zipfile.ZipFile(zip_path)
    entries = [(info, decode_name(info)) for info in zf.infolist()
               if not info.is_dir() and decode_name(info).lower().endswith(".xlsx")]

    n_ok, n_skip, n_err = 0, 0, 0
    for sec_key, sec_kw, sec_excl in MEASURES:
        for axis_key, axis_kw, subtree in AXES:
            prefix = f"{sec_key}_{axis_key}"
            dest_dir = os.path.join(rawdata_dl, subtree, prefix)
            os.makedirs(dest_dir, exist_ok=True)
            dest = os.path.join(dest_dir, f"ndb{edition:02d}_{prefix}_{fy}.xlsx")

            if os.path.exists(dest):
                print(f"  [skip] {os.path.basename(dest)} (既存)")
                n_skip += 1
                continue

            # 該当エントリを抽出: フォルダがsec_kwを含み(除外語を含まず)、
            # ファイル名がaxis_kwを含み、診療月別でないもの
            cand = []
            for info, name in entries:
                folder = os.path.dirname(name)
                base = os.path.basename(name)
                if sec_kw not in folder:
                    continue
                if sec_excl and sec_excl in folder:
                    continue
                if axis_kw not in base or EXCLUDE_AXIS in base:
                    continue
                cand.append((info, name))

            if len(cand) != 1:
                print(f"  [ERR ] {prefix}: 候補 {len(cand)} 件 "
                      f"(期待1件) -> {[n for _, n in cand]}")
                n_err += 1
                continue

            info, name = cand[0]
            with zf.open(info) as src, open(dest, "wb") as out:
                out.write(src.read())
            print(f"  [ ok ] {os.path.basename(dest)}  <=  {name}")
            n_ok += 1

    print(f"\n抽出結果: ok={n_ok}, skip={n_skip}, error={n_err}")
    sys.exit(1 if n_err else 0)


if __name__ == "__main__":
    main()
