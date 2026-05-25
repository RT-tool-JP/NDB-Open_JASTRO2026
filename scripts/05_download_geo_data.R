################################################################################
# 05_download_geo_data.R
# 地理データ ダウンロード
#
# 1. 都道府県GeoJSON (smartnews-smri/japan-topography)
# 2. 二次医療圏GeoJSON (国土数値情報 A38 or 加工済みソース)
# 3. 二次医療圏マッピング (厚労省 病院報告 付録)
################################################################################

data_dir <- file.path(getwd(), "rawdata_dl", "geo")
dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)

cat("=== 地理データ ダウンロード ===\n\n")

# =============================================================================
# 1. 都道府県 GeoJSON
# =============================================================================
pref_geojson <- file.path(data_dir, "prefectures.geojson")

if (!file.exists(pref_geojson)) {
  cat("都道府県GeoJSON => downloading...")
  tryCatch({
    download.file(
      "https://raw.githubusercontent.com/smartnews-smri/japan-topography/main/data/municipality/geojson/s0010/prefectures.json",
      pref_geojson, mode = "wb", quiet = TRUE)
    cat(sprintf(" OK (%s bytes)\n", format(file.size(pref_geojson), big.mark = ",")))
  }, error = function(e) cat(sprintf(" ERROR: %s\n", e$message)))
} else {
  cat("都道府県GeoJSON => skip\n")
}

# =============================================================================
# 2. 二次医療圏 GeoJSON
# =============================================================================
# 国土数値情報 A38 (二次医療圏) のダウンロード
# 最新版(令和6年)を使用。形式: GeoJSON (GitHub上の加工済みデータ)
# または Shapefile をダウンロードして変換

sma_geojson <- file.path(data_dir, "sma.geojson")

if (!file.exists(sma_geojson)) {
  cat("\n二次医療圏GeoJSON => downloading...\n")

  # 方法1: 国土数値情報から直接Shapefileをダウンロードし、sfパッケージで変換
  sma_zip <- file.path(data_dir, "A38_sma.zip")
  sma_extracted <- file.path(data_dir, "A38_extracted")

  # 国土数値情報 A38 最新版ダウンロード
  # URL形式: https://nlftp.mlit.go.jp/ksj/gml/data/A38/A38-YYMMDD/A38-YYMMDD_GML.zip
  # 最新版はページ上で確認が必要
  # ここでは令和4年(2022)版を試行
  a38_urls <- c(
    "https://nlftp.mlit.go.jp/ksj/gml/data/A38/A38-22/A38-22_GML.zip",
    "https://nlftp.mlit.go.jp/ksj/gml/data/A38/A38-21/A38-21_GML.zip",
    "https://nlftp.mlit.go.jp/ksj/gml/data/A38/A38-20/A38-20_GML.zip"
  )

  downloaded <- FALSE
  for (url in a38_urls) {
    cat(sprintf("  Trying: %s ...", basename(url)))
    tryCatch({
      download.file(url, sma_zip, mode = "wb", quiet = TRUE)
      if (file.size(sma_zip) > 1000) {
        cat(" OK\n")
        downloaded <- TRUE
        break
      } else {
        cat(" (too small, trying next)\n")
        file.remove(sma_zip)
      }
    }, error = function(e) {
      cat(sprintf(" ERROR: %s\n", e$message))
    })
    Sys.sleep(1)
  }

  if (downloaded) {
    # ZIP解凍
    dir.create(sma_extracted, recursive = TRUE, showWarnings = FALSE)
    unzip(sma_zip, exdir = sma_extracted)

    # Shapefile → GeoJSON 変換 (sfパッケージ使用)
    cat("  Shapefile → GeoJSON 変換中...\n")
    tryCatch({
      library(sf)

      # .shp ファイルを探す
      shp_files <- list.files(sma_extracted, pattern = "\\.shp$",
                               recursive = TRUE, full.names = TRUE)

      if (length(shp_files) > 0) {
        # 二次医療圏のshpを選択 (ファイル名に A38 を含むもの)
        shp_file <- shp_files[1]
        cat(sprintf("  Reading: %s\n", basename(shp_file)))

        sma_sf <- st_read(shp_file, quiet = TRUE)
        cat(sprintf("  Features: %d, CRS: %s\n", nrow(sma_sf), st_crs(sma_sf)$epsg))

        # WGS84に変換
        if (!is.na(st_crs(sma_sf)$epsg) && st_crs(sma_sf)$epsg != 4326) {
          sma_sf <- st_transform(sma_sf, 4326)
        }

        # 簡略化 (webapp用に軽量化)
        sma_sf <- st_simplify(sma_sf, dTolerance = 0.005, preserveTopology = TRUE)

        # GeoJSON出力
        st_write(sma_sf, sma_geojson, driver = "GeoJSON", delete_dsn = TRUE, quiet = TRUE)
        cat(sprintf("  GeoJSON出力: %s (%s bytes)\n",
                    sma_geojson, format(file.size(sma_geojson), big.mark = ",")))
      } else {
        # GMLファイルを試す
        gml_files <- list.files(sma_extracted, pattern = "\\.gml$",
                                 recursive = TRUE, full.names = TRUE)
        if (length(gml_files) > 0) {
          gml_file <- gml_files[1]
          cat(sprintf("  Reading GML: %s\n", basename(gml_file)))
          sma_sf <- st_read(gml_file, quiet = TRUE)
          if (!is.na(st_crs(sma_sf)$epsg) && st_crs(sma_sf)$epsg != 4326) {
            sma_sf <- st_transform(sma_sf, 4326)
          }
          sma_sf <- st_simplify(sma_sf, dTolerance = 0.005, preserveTopology = TRUE)
          st_write(sma_sf, sma_geojson, driver = "GeoJSON", delete_dsn = TRUE, quiet = TRUE)
          cat(sprintf("  GeoJSON出力: %s (%s bytes)\n",
                      sma_geojson, format(file.size(sma_geojson), big.mark = ",")))
        } else {
          cat("  WARNING: ShapefileもGMLも見つかりませんでした\n")
          # ファイル一覧を表示
          all_files <- list.files(sma_extracted, recursive = TRUE)
          cat("  解凍されたファイル:\n")
          for (f in all_files) cat(sprintf("    %s\n", f))
        }
      }
    }, error = function(e) {
      cat(sprintf("  ERROR in conversion: %s\n", e$message))
      cat("  sfパッケージが必要です: install.packages('sf')\n")
    })
  } else {
    cat("  WARNING: 国土数値情報 A38 のダウンロードに失敗しました\n")
    cat("  手動でダウンロードしてください:\n")
    cat("  https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-A38.html\n")
  }
} else {
  cat("\n二次医療圏GeoJSON => skip\n")
}

# =============================================================================
# 3. 二次医療圏マッピングテーブル
# =============================================================================
# 厚労省 病院報告等の付録にある二次医療圏・市区町村対応表
# e-Stat: 患者調査 付録 (statInfId=000031348710) or 病院報告付録

sma_mapping <- file.path(data_dir, "sma_mapping_raw.csv")

if (!file.exists(sma_mapping)) {
  cat("\n二次医療圏マッピング => downloading...")
  # 患者調査の二次医療圏対応表
  tryCatch({
    download.file(
      "https://www.e-stat.go.jp/stat-search/file-download?statInfId=000031348710&fileKind=0",
      sma_mapping, mode = "wb", quiet = TRUE)
    cat(sprintf(" OK (%s bytes)\n", format(file.size(sma_mapping), big.mark = ",")))
  }, error = function(e) {
    cat(sprintf(" ERROR: %s\n", e$message))
    # 代替: 病院報告の対応表
    cat("  代替ソースを試行中...\n")
    tryCatch({
      download.file(
        "https://www.e-stat.go.jp/stat-search/file-download?statInfId=000040224319&fileKind=0",
        sma_mapping, mode = "wb", quiet = TRUE)
      cat(sprintf("  代替ソース OK (%s bytes)\n", format(file.size(sma_mapping), big.mark = ",")))
    }, error = function(e2) {
      cat(sprintf("  代替ソースも失敗: %s\n", e2$message))
    })
  })
} else {
  cat("\n二次医療圏マッピング => skip\n")
}

# =============================================================================
# データ構造の確認
# =============================================================================
cat("\n=== ダウンロード済みファイル一覧 ===\n")
all_files <- list.files(data_dir, recursive = TRUE, full.names = TRUE)
for (f in all_files) {
  cat(sprintf("  %s (%s bytes)\n", basename(f),
              format(file.size(f), big.mark = ",")))
}

# 二次医療圏GeoJSONの属性確認
if (file.exists(sma_geojson)) {
  tryCatch({
    library(sf)
    sma <- st_read(sma_geojson, quiet = TRUE)
    cat(sprintf("\n二次医療圏GeoJSON: %d features\n", nrow(sma)))
    cat("属性名:\n")
    for (cn in names(sma)) {
      if (cn != "geometry") {
        cat(sprintf("  %s: %s (例: %s)\n", cn, class(sma[[cn]])[1],
                    as.character(sma[[cn]][1])))
      }
    }
  }, error = function(e) {
    cat(sprintf("GeoJSON確認エラー: %s\n", e$message))
  })
}

cat("\n=== 地理データ ダウンロード完了 ===\n")
