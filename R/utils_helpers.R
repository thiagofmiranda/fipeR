# ============================================================
# Helpers de UI / formatacao
# ============================================================

#' Icone Bootstrap (wrapper sobre bsicons).
#' @noRd
bsicon <- function(name, ...) {
  bsicons::bs_icon(name, ...)
}

#' Formata numero como moeda BRL.
#' @noRd
fmt_brl <- function(x) {
  scales::label_dollar(
    prefix = "R$ ", big.mark = ".", decimal.mark = ",", accuracy = 1
  )(x)
}

#' Paleta de cores do dashboard (n cores).
#' @noRd
pal_fipe <- function(n) {
  base <- c("#2563eb", "#16a34a", "#f59e0b", "#dc2626", "#7c3aed",
            "#0891b2", "#db2777", "#65a30d", "#ea580c", "#475569")
  if (n <= length(base)) return(base[seq_len(max(n, 1))])
  grDevices::colorRampPalette(base)(n)
}
