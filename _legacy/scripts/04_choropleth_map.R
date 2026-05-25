################################################################################
# 04_choropleth_map.R
# 都道府県別 人口あたり算定回数のコロプレスマップ（塗り分け地図）
#
# 地理データ元: 国土数値情報 行政区域データ（N03）を基に簡素化したGeoJSON
#   原典: 国土交通省 国土数値情報 https://nlftp.mlit.go.jp/ksj/
#   利用ファイル: smartnews-smri/japan-topography (GitHub)
#     https://github.com/smartnews-smri/japan-topography
#   ※国土数値情報 N03（行政区域）を都道府県単位に集約・簡素化したもの
################################################################################

library(sf)
library(dplyr)
library(ggplot2)

# =============================================================================
# 設定
# =============================================================================

TARGET_CODE <- "M001"  # 体外照射（02_/03_ と合わせる）

data_dir   <- here::here("rawdata")
output_dir <- here::here("output")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

pref_names <- c(
  "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
  "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
  "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県",
  "岐阜県", "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府",
  "兵庫県", "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県",
  "広島県", "山口県", "徳島県", "香川県", "愛媛県", "高知県",
  "福岡県", "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"
)

# =============================================================================
# 1. 都道府県境界GeoJSONのダウンロード・読み込み
# =============================================================================

cat("=== 地理データの読み込み ===\n")

geojson_path <- file.path(data_dir, "prefectures.geojson")

if (!file.exists(geojson_path)) {
  cat("都道府県境界GeoJSONをダウンロード中...\n")
  # 国土数値情報 N03 を都道府県に集約・簡素化したデータ
  download.file(
    "https://raw.githubusercontent.com/smartnews-smri/japan-topography/main/data/municipality/geojson/s0010/prefectures.json",
    geojson_path, mode = "wb", quiet = TRUE
  )
}

jp_pref <- st_read(geojson_path, quiet = TRUE)
cat(sprintf("都道府県ポリゴン: %d features\n", nrow(jp_pref)))

# 列名を統一
colnames(jp_pref)[colnames(jp_pref) == "N03_001"] <- "pref_name"

# =============================================================================
# 2. 人口あたり算定回数データの読み込み
# =============================================================================

cat("\n=== 算定回数データの読み込み ===\n")

percapita_csv <- file.path(output_dir, sprintf("%s_percapita_detail.csv", TARGET_CODE))
if (!file.exists(percapita_csv)) {
  stop("人口あたりデータが見つかりません。先に 03_per_capita_analysis.R を実行してください。")
}

percapita <- read.csv(percapita_csv, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
cat(sprintf("算定回数データ: %d records\n", nrow(percapita)))

# =============================================================================
# 3. 地理データと算定回数データの結合
# =============================================================================

latest_year <- max(percapita$year)

# 最新年度のデータ
pc_latest <- percapita |>
  filter(year == latest_year) |>
  select(pref_name, total_count, population, count_per_100k)

jp_data <- jp_pref |>
  left_join(pc_latest, by = "pref_name")

cat(sprintf("結合結果: %d features (年度: %d)\n", nrow(jp_data), latest_year))

# 全年度データも結合（複数年マップ用）
jp_all_years <- jp_pref |>
  left_join(percapita |> select(pref_name, year, count_per_100k), by = "pref_name")

# =============================================================================
# 4. コロプレスマップ描画
# =============================================================================

cat("\n=== コロプレスマップ作成 ===\n")

class_name_short <- if (TARGET_CODE == "M001") "体外照射" else TARGET_CODE

# 全国平均
nat_avg <- sum(pc_latest$total_count) / sum(pc_latest$population) * 100000

# --- 4a. 本州・四国・九州メインマップ + 北海道・沖縄インセット ---
# 沖縄の位置を調整して見やすくする

# メイン領域（北海道〜九州）の bbox
main_xlim <- c(128, 146)
main_ylim <- c(30.5, 45.5)

g_main <- ggplot(jp_data) +
  geom_sf(aes(fill = count_per_100k), color = "white", linewidth = 0.2) +
  scale_fill_viridis_c(
    option = "C",
    name = "人口10万人\nあたり算定回数",
    labels = scales::comma,
    breaks = scales::pretty_breaks(n = 6)
  ) +
  coord_sf(xlim = main_xlim, ylim = main_ylim) +
  labs(
    title = sprintf("%s（%s）人口10万人あたり算定回数（%d年度）",
                     TARGET_CODE, class_name_short, latest_year),
    subtitle = sprintf(
      "全国平均: %.0f回/10万人 | データ: NDB Open Data・総務省人口推計・国土数値情報",
      nat_avg
    ),
    caption = "地理データ: 国土交通省 国土数値情報（N03 行政区域）"
  ) +
  theme_void(base_family = "HiraginoSans-W3") +
  theme(
    plot.title    = element_text(size = 14, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(size = 9, hjust = 0.5, color = "grey40"),
    plot.caption  = element_text(size = 7, color = "grey60"),
    legend.position = c(0.15, 0.35),
    legend.title  = element_text(size = 8),
    legend.text   = element_text(size = 7),
    plot.margin   = margin(10, 10, 10, 10)
  )

ggsave(file.path(output_dir, sprintf("%s_choropleth_%d.png", TARGET_CODE, latest_year)),
       g_main, width = 10, height = 10, dpi = 200, bg = "white")
cat(sprintf("  全国マップ: %s_choropleth_%d.png\n", TARGET_CODE, latest_year))

# --- 4b. 全国平均との乖離率マップ ---
jp_data <- jp_data |>
  mutate(
    deviation = (count_per_100k - nat_avg) / nat_avg * 100
  )

g_dev <- ggplot(jp_data) +
  geom_sf(aes(fill = deviation), color = "white", linewidth = 0.2) +
  scale_fill_gradient2(
    low = "#2166AC", mid = "#F7F7F7", high = "#B2182B",
    midpoint = 0,
    name = "全国平均との\n乖離率（%）",
    labels = function(x) sprintf("%+.0f%%", x)
  ) +
  coord_sf(xlim = main_xlim, ylim = main_ylim) +
  labs(
    title = sprintf("%s（%s）全国平均からの乖離率（%d年度）",
                     TARGET_CODE, class_name_short, latest_year),
    subtitle = sprintf(
      "全国平均: %.0f回/10万人 | 赤=平均以上 青=平均以下",
      nat_avg
    ),
    caption = "データ: NDB Open Data・総務省人口推計 | 地理データ: 国土数値情報（N03）"
  ) +
  theme_void(base_family = "HiraginoSans-W3") +
  theme(
    plot.title    = element_text(size = 14, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(size = 9, hjust = 0.5, color = "grey40"),
    plot.caption  = element_text(size = 7, color = "grey60"),
    legend.position = c(0.15, 0.35),
    legend.title  = element_text(size = 8),
    legend.text   = element_text(size = 7),
    plot.margin   = margin(10, 10, 10, 10)
  )

ggsave(file.path(output_dir, sprintf("%s_deviation_map_%d.png", TARGET_CODE, latest_year)),
       g_dev, width = 10, height = 10, dpi = 200, bg = "white")
cat(sprintf("  乖離率マップ: %s_deviation_map_%d.png\n", TARGET_CODE, latest_year))

# --- 4c. 年度別 小さなコロプレスマップ（ファセット） ---
# 全年度データ
all_years_data <- percapita |>
  select(pref_name, year, count_per_100k)

jp_facet <- jp_pref |>
  left_join(all_years_data, by = "pref_name")

# 全年度の値域を統一
val_range <- range(jp_facet$count_per_100k, na.rm = TRUE)

g_facet <- ggplot(jp_facet) +
  geom_sf(aes(fill = count_per_100k), color = "grey70", linewidth = 0.05) +
  scale_fill_viridis_c(
    option = "C",
    name = "10万人あたり",
    labels = scales::comma,
    limits = val_range
  ) +
  coord_sf(xlim = main_xlim, ylim = main_ylim) +
  facet_wrap(~ year, ncol = 5) +
  labs(
    title = sprintf("%s（%s）人口10万人あたり算定回数の年度推移",
                     TARGET_CODE, class_name_short),
    caption = "データ: NDB Open Data・総務省人口推計 | 地理データ: 国土数値情報（N03）"
  ) +
  theme_void(base_family = "HiraginoSans-W3") +
  theme(
    plot.title     = element_text(size = 14, face = "bold", hjust = 0.5),
    plot.caption   = element_text(size = 7, color = "grey60"),
    strip.text     = element_text(size = 10, face = "bold"),
    legend.position = "bottom",
    legend.key.width = unit(2, "cm"),
    legend.title   = element_text(size = 8),
    legend.text    = element_text(size = 7)
  )

ggsave(file.path(output_dir, sprintf("%s_choropleth_years.png", TARGET_CODE)),
       g_facet, width = 16, height = 8, dpi = 200, bg = "white")
cat(sprintf("  年度別マップ: %s_choropleth_years.png\n", TARGET_CODE))

cat("\n=== 処理完了 ===\n")
