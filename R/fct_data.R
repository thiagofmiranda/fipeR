# ============================================================
# Camada de dados: leitura e tratamento dos datasets parquet.
# ============================================================

#' Converte "R$ 184.026,00" -> 184026 (numeric).
#' @noRd
fipe_currency_to_numeric <- function(x) {
  x |>
    stringr::str_replace_all("R\\$\\s*", "") |>
    stringr::str_replace_all("\\.", "") |>
    stringr::str_replace(",", ".") |>
    as.numeric()
}

#' Converte "setembro de 2022" -> Date (2022-09-01).
#' @noRd
fipe_month_to_date <- function(x) {
  meses <- c(janeiro = "01", fevereiro = "02", "março" = "03", marco = "03",
             abril = "04", maio = "05", junho = "06", julho = "07",
             agosto = "08", setembro = "09", outubro = "10",
             novembro = "11", dezembro = "12")
  x <- stringr::str_trim(stringr::str_to_lower(x))
  mes <- stringr::str_extract(x, "^[^ ]+")
  ano <- stringr::str_extract(x, "\\d{4}")
  as.Date(paste0(ano, "-", meses[mes], "-01"))
}

#' Le e trata o dataset de precos.
#'
#' Coleta tudo, converte moeda/data, deriva `anoReferencia` e rotula o
#' ano-modelo 32000 como "0 km".
#'
#' @param data_dir diretorio raiz dos dados.
#' @return tibble tratado, ou tibble vazio se o dataset nao existir.
#' @export
fipe_load_prices <- function(data_dir = "data") {
  path <- file.path(data_dir, "prices")
  if (!dir.exists(path)) {
    return(dplyr::tibble())
  }

  df <- arrow::open_dataset(path) |>
    dplyr::collect()

  if (nrow(df) == 0) return(df)

  df |>
    dplyr::mutate(
      valor = fipe_currency_to_numeric(.data$valorCarro),
      data = fipe_month_to_date(.data$mesReferencia),
      anoReferencia = lubridate::year(.data$data),
      # Origem do ponto: o 0km (32000) e' o carro de vitrine daquele mes.
      origem_0km = .data$anoModelo == 32000
    ) |>
    # Resolve o 0km como (maior ano real DO MODELO naquele mes) + 1: o
    # ano-modelo "novo" daquele modelo no mes de referencia. Como e' sempre
    # > todos os anos reais do modelo no mes, nunca colide com um ano
    # existente. Quando o ano novo e' lancado pela FIPE, o 0km "passa o
    # bastao" e migra para o ano seguinte.
    #
    # Fallback (modelo so tem o ponto 0km no mes): usa o maior ano real do
    # MES INTEIRO + 1, em vez de somar no ano de referencia.
    dplyr::group_by(.data$data) |>
    dplyr::mutate(
      # Maior ano real do mes inteiro (todos os modelos); -Inf vira NA em
      # DOUBLE p/ nenhum as.integer tocar em valor infinito (evita warnings).
      max_real_mes = suppressWarnings(max(.data$anoModelo[!.data$origem_0km], na.rm = TRUE)),
      max_real_mes = ifelse(is.finite(.data$max_real_mes), .data$max_real_mes, NA_real_)
    ) |>
    dplyr::group_by(.data$modelo, .data$data) |>
    dplyr::mutate(
      # Maior ano real do modelo naquele mes.
      max_real = suppressWarnings(max(.data$anoModelo[!.data$origem_0km], na.rm = TRUE)),
      max_real = ifelse(is.finite(.data$max_real), .data$max_real, NA_real_),
      anoModelo = dplyr::case_when(
        !.data$origem_0km          ~ as.integer(.data$anoModelo),
        !is.na(.data$max_real)     ~ as.integer(.data$max_real) + 1L,
        !is.na(.data$max_real_mes) ~ as.integer(.data$max_real_mes) + 1L,
        # Ultimo recurso: mes inteiro so tem 0km (nao deve ocorrer na FIPE).
        TRUE                       ~ as.integer(.data$anoReferencia) + 1L
      )
    ) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      anoModeloLabel = as.character(.data$anoModelo),
      anoOrdem = .data$anoModelo,
      serie = paste0(.data$modelo, " (", .data$anoModeloLabel, ")")
    ) |>
    dplyr::select(-"max_real", -"max_real_mes") |>
    dplyr::filter(!is.na(.data$data), !is.na(.data$valor)) |>
    dplyr::arrange(.data$data)
}

#' Catalogo de carros disponiveis para download (cars + models + marcas).
#'
#' Usado pelo modulo de download para popular os seletores sem bater na API.
#' @noRd
fipe_catalogo <- function(data_dir = "data") {
  path_cars <- file.path(data_dir, "cars")
  path_models <- file.path(data_dir, "models")
  if (!dir.exists(path_cars) || !dir.exists(path_models)) {
    return(dplyr::tibble())
  }

  models <- arrow::open_dataset(path_models) |> dplyr::collect()
  cars <- arrow::open_dataset(path_cars) |> dplyr::collect()

  cars |>
    dplyr::left_join(
      models,
      by = c("codigoTipoVeiculo", "codigoTabelaReferencia",
             "codigoMarca", "codigoModelo")
    ) |>
    dplyr::mutate(
      anoModeloLabel = ifelse(.data$anoModelo == 32000, "0 km",
                              as.character(.data$anoModelo))
    )
}
