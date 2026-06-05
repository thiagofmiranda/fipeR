# ============================================================
# Prototipo: compara o layout de precos ANTIGO (6 niveis de particao)
# com o ACHATADO (codigoTipoVeiculo / codigoMarca).
#
# Roda sobre os dados JA em disco (nao baixa nada da API). Mede:
#   - numero de arquivos parquet
#   - tempo de leitura (open_dataset |> collect)
#   - integridade (mesma contagem de linhas)
#
# Uso:
#   pkgload::load_all(".")          # carrega as funcoes do pacote
#   source("dev/prototipo_particao_achatada.R")
# ============================================================

if (!requireNamespace("pkgload", quietly = TRUE)) {
  stop("Instale {pkgload} ou use devtools::load_all() antes de rodar.")
}
pkgload::load_all(".", quiet = TRUE)

library(arrow)
library(dplyr)

data_dir <- "data"
src <- file.path(data_dir, "prices")
stopifnot(dir.exists(src))

cat("==================================================\n")
cat("Layout ANTIGO (em disco):", src, "\n")

files_old <- list.files(src, pattern = "\\.parquet$", recursive = TRUE)
t_old <- system.time(d_old <- arrow::open_dataset(src) |> dplyr::collect())
cat("  arquivos parquet:", length(files_old), "\n")
cat("  linhas          :", nrow(d_old), "\n")
cat("  leitura (s)     :", round(t_old[["elapsed"]], 3), "\n")

# --- Migra para layout achatado em diretorio temporario -----------
dest <- file.path(tempdir(), "fipe_flat")
unlink(dest, recursive = TRUE)
n_mig <- fipe_migrar_prices_layout(data_dir = data_dir, dest_dir = dest)
flat <- file.path(dest, "prices")

cat("--------------------------------------------------\n")
cat("Layout ACHATADO (migrado):", flat, "\n")

files_new <- list.files(flat, pattern = "\\.parquet$", recursive = TRUE)
t_new <- system.time(d_new <- arrow::open_dataset(flat) |> dplyr::collect())
cat("  arquivos parquet:", length(files_new), "\n")
cat("  linhas          :", nrow(d_new), "\n")
cat("  leitura (s)     :", round(t_new[["elapsed"]], 3), "\n")

# --- Tamanho em disco ---------------------------------------------
size_dir <- function(p) {
  fs <- list.files(p, recursive = TRUE, full.names = TRUE)
  sum(file.info(fs)$size, na.rm = TRUE)
}
cat("--------------------------------------------------\n")
cat("Tamanho antigo  :", round(size_dir(src) / 1024, 1), "KB\n")
cat("Tamanho achatado:", round(size_dir(flat) / 1024, 1), "KB\n")

# --- Integridade ---------------------------------------------------
stopifnot(nrow(d_old) == nrow(d_new))
cat("==================================================\n")
cat("OK: mesma contagem de linhas (", nrow(d_old), ").\n", sep = "")
cat("Reducao de arquivos:", length(files_old), "->", length(files_new),
    sprintf("(%.0f%%)\n", 100 * (1 - length(files_new) / max(length(files_old), 1))))

# Validacao extra: pos-migracao, fipe_load_prices ainda funciona no flat.
tratado <- fipe_load_prices(dest)
cat("fipe_load_prices(flat): ", nrow(tratado), " linhas tratadas, ",
    ncol(tratado), " colunas.\n", sep = "")
