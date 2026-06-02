# ============================================================
# Camada de download: grava datasets parquet particionados.
# ============================================================

#' Baixa os modelos de uma marca e grava em `data/models`.
#' @noRd
downloadModels <- function(codigoTipoVeiculo, codigoTabelaReferencia, codigoMarca,
                           data_dir = "data") {
  df <- consultarModelos(
    codigoTipoVeiculo = codigoTipoVeiculo,
    codigoMarca = codigoMarca,
    codigoTabelaReferencia = codigoTabelaReferencia
  )
  arrow::write_dataset(
    df,
    path = file.path(data_dir, "models"),
    partitioning = c("codigoTipoVeiculo", "codigoTabelaReferencia", "codigoMarca"),
    format = "parquet",
    existing_data_behavior = "overwrite"
  )
  invisible(df)
}

#' Baixa anos/combustivel de um modelo e grava em `data/cars`.
#' @noRd
downloadCars <- function(codigoModelo, codigoMarca,
                         codigoTabelaReferencia = 333, codigoTipoVeiculo = 1,
                         data_dir = "data") {
  df <- consultarAnoModelo(
    codigoModelo = codigoModelo,
    codigoMarca = codigoMarca,
    codigoTabelaReferencia = codigoTabelaReferencia,
    codigoTipoVeiculo = codigoTipoVeiculo
  ) |>
    tidyr::separate_wider_delim(
      "Label", delim = " ",
      names = c("ano", "tipoCombustivel"), too_many = "merge"
    ) |>
    tidyr::separate_wider_delim(
      "Value", delim = "-",
      names = c("anoModelo", "codigoTipoCombustivel")
    ) |>
    dplyr::mutate(
      anoModelo = as_int(.data$anoModelo),
      codigoTipoCombustivel = as_int(.data$codigoTipoCombustivel)
    )

  arrow::write_dataset(
    df,
    path = file.path(data_dir, "cars"),
    partitioning = c("codigoTipoVeiculo", "codigoTabelaReferencia",
                     "codigoMarca", "codigoModelo"),
    format = "parquet",
    existing_data_behavior = "overwrite"
  )
  invisible(df)
}

#' Baixa o preco de um carro/ano/tabela e grava em `data/prices`.
#'
#' Idempotente: pula se a particao ja existe.
#' @noRd
downloadPrices <- function(codigoTipoVeiculo, codigoMarca, codigoModelo,
                           anoModelo, codigoTipoCombustivel, codigoTabelaReferencia,
                           data_dir = "data") {
  ja_existe <- Sys.glob(file.path(
    data_dir, "prices",
    paste0("codigoTipoVeiculo=", codigoTipoVeiculo),
    paste0("codigoTabelaReferencia=", codigoTabelaReferencia),
    paste0("codigoMarca=", codigoMarca),
    paste0("codigoModelo=", codigoModelo),
    "codigoFipe=*",
    paste0("anoModelo=", anoModelo)
  ))
  if (length(ja_existe) > 0) {
    return(invisible(NULL))
  }

  df <- consultarValorComTodosParametros(
    codigoTipoVeiculo = codigoTipoVeiculo,
    codigoMarca = codigoMarca,
    codigoModelo = codigoModelo,
    anoModelo = anoModelo,
    codigoTipoCombustivel = codigoTipoCombustivel,
    codigoTabelaReferencia = codigoTabelaReferencia
  )

  arrow::write_dataset(
    df,
    path = file.path(data_dir, "prices"),
    partitioning = c("codigoTipoVeiculo", "codigoTabelaReferencia", "codigoMarca",
                     "codigoModelo", "codigoFipe", "anoModelo"),
    format = "parquet",
    existing_data_behavior = "overwrite"
  )
  invisible(df)
}

# Versoes resilientes para uso em lote.
downloadModels_safe <- purrr::possibly(downloadModels, otherwise = NULL)
downloadCars_safe   <- purrr::possibly(downloadCars, otherwise = NULL)
downloadPrices_safe <- purrr::possibly(downloadPrices, otherwise = NULL)

#' Baixa precos para um conjunto de combinacoes carro x tabela de referencia.
#'
#' Iterador com callback de progresso, pensado para a UI Shiny.
#'
#' @param plano data.frame com colunas codigoTipoVeiculo, codigoMarca,
#'   codigoModelo, anoModelo, codigoTipoCombustivel, codigoTabelaReferencia.
#' @param data_dir diretorio raiz dos dados.
#' @param on_progress funcao(i, n, linha) chamada a cada iteracao.
#' @noRd
baixar_precos_em_lote <- function(plano, data_dir = "data", on_progress = NULL) {
  n <- nrow(plano)
  if (n == 0) return(invisible(0L))
  baixados <- 0L
  for (i in seq_len(n)) {
    linha <- plano[i, ]
    res <- downloadPrices_safe(
      codigoTipoVeiculo = linha$codigoTipoVeiculo,
      codigoMarca = linha$codigoMarca,
      codigoModelo = linha$codigoModelo,
      anoModelo = linha$anoModelo,
      codigoTipoCombustivel = linha$codigoTipoCombustivel,
      codigoTabelaReferencia = linha$codigoTabelaReferencia,
      data_dir = data_dir
    )
    if (!is.null(res)) baixados <- baixados + 1L
    if (is.function(on_progress)) on_progress(i, n, linha)
  }
  invisible(baixados)
}
