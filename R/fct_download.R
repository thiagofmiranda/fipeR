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

# ------------------------------------------------------------
# Precos: particao ACHATADA (codigoTipoVeiculo / codigoMarca).
#
# Antes a particao tinha 6 niveis (.../codigoModelo/codigoFipe/anoModelo),
# o que gerava milhares de parquets minusculos (~1.5k so para um modelo).
# Agora uma marca inteira mora em um unico parquet por tipo de veiculo:
# poucos arquivos grandes, leitura rapida e compressao colunar efetiva.
# ------------------------------------------------------------

#' Colunas que identificam unicamente uma observacao de preco.
#'
#' (mesReferencia e' 1:1 com codigoTabelaReferencia; codigoFipe e' derivado do
#' modelo -- nenhum dos dois entra na chave.)
#' @noRd
fipe_prices_keys <- function() {
  c("codigoTipoVeiculo", "codigoTabelaReferencia", "codigoMarca",
    "codigoModelo", "anoModelo", "codigoTipoCombustivel")
}

#' Colunas de particao do dataset de precos (layout achatado).
#' @noRd
fipe_prices_partition <- function() c("codigoTipoVeiculo", "codigoMarca")

#' Normaliza as colunas-chave para inteiro.
#'
#' Dados gravados por versoes antigas podem ter chaves como texto (ex.:
#' `codigoTipoCombustivel` veio como <chr>), o que quebra joins/dedup contra o
#' plano (que e' <int>). Forca a chave para inteiro de forma consistente.
#' @noRd
fipe_coerce_keys <- function(df) {
  chaves <- intersect(fipe_prices_keys(), names(df))
  if (length(chaves) == 0) return(df)
  dplyr::mutate(df, dplyr::across(dplyr::all_of(chaves), as_int))
}

#' Busca na API o preco de um carro/ano/tabela (NAO grava).
#'
#' Diferente do antigo `downloadPrices`, so faz a consulta e devolve a linha;
#' a gravacao deduplicada fica a cargo de [fipe_write_prices()].
#' @return data.frame de 1 linha.
#' @noRd
fetchPrice <- function(codigoTipoVeiculo, codigoMarca, codigoModelo,
                       anoModelo, codigoTipoCombustivel, codigoTabelaReferencia) {
  consultarValorComTodosParametros(
    codigoTipoVeiculo = codigoTipoVeiculo,
    codigoMarca = codigoMarca,
    codigoModelo = codigoModelo,
    anoModelo = anoModelo,
    codigoTipoCombustivel = codigoTipoCombustivel,
    codigoTabelaReferencia = codigoTabelaReferencia
  )
}

# Versoes resilientes para uso em lote.
downloadModels_safe <- purrr::possibly(downloadModels, otherwise = NULL)
downloadCars_safe   <- purrr::possibly(downloadCars, otherwise = NULL)
fetchPrice_safe     <- purrr::possibly(fetchPrice, otherwise = NULL)

#' Chaves de preco ja gravadas em disco.
#'
#' Usada para (a) nao baixar da API o que ja existe e (b) deduplicar. Aceita
#' restringir as particoes lidas (`tipos`/`marcas`) para aproveitar o pushdown
#' da particao achatada e nao varrer o dataset inteiro.
#'
#' @return tibble com as colunas de [fipe_prices_keys()] (0 linhas se vazio).
#' @noRd
fipe_prices_existentes <- function(data_dir = "data", tipos = NULL, marcas = NULL) {
  chaves <- fipe_prices_keys()
  vazio <- dplyr::as_tibble(stats::setNames(
    replicate(length(chaves), integer(0), simplify = FALSE), chaves
  ))
  path <- file.path(data_dir, "prices")
  if (!dir.exists(path)) return(vazio)
  ds <- tryCatch(arrow::open_dataset(path), error = function(e) NULL)
  if (is.null(ds)) return(vazio)
  q <- ds
  if (!is.null(tipos))  q <- dplyr::filter(q, .data$codigoTipoVeiculo %in% !!tipos)
  if (!is.null(marcas)) q <- dplyr::filter(q, .data$codigoMarca %in% !!marcas)
  out <- tryCatch(
    q |>
      dplyr::select(dplyr::any_of(chaves)) |>
      dplyr::collect(),
    error = function(e) NULL
  )
  if (is.null(out)) return(vazio)
  fipe_coerce_keys(out) |> dplyr::distinct()
}

#' Le as linhas COMPLETAS das particoes tocadas por um lote.
#'
#' Faz semi-join pelo par (tipoVeiculo, marca) para nunca regravar particoes
#' vizinhas que so foram lidas por causa do pushdown amplo.
#' @noRd
fipe_prices_full_particoes <- function(data_dir, particoes) {
  path <- file.path(data_dir, "prices")
  if (!dir.exists(path)) return(NULL)
  ds <- tryCatch(arrow::open_dataset(path), error = function(e) NULL)
  if (is.null(ds)) return(NULL)
  out <- tryCatch(
    ds |>
      dplyr::filter(
        .data$codigoTipoVeiculo %in% !!unique(particoes$codigoTipoVeiculo),
        .data$codigoMarca %in% !!unique(particoes$codigoMarca)
      ) |>
      dplyr::collect(),
    error = function(e) NULL
  )
  if (is.null(out) || nrow(out) == 0) return(out)
  out <- fipe_coerce_keys(out)
  dplyr::semi_join(out, particoes, by = c("codigoTipoVeiculo", "codigoMarca"))
}

#' Remove do plano as combinacoes ja gravadas (evita re-download).
#' @noRd
fipe_filtrar_plano_novo <- function(plano, data_dir = "data") {
  if (nrow(plano) == 0) return(plano)
  existentes <- fipe_prices_existentes(
    data_dir,
    tipos = unique(plano$codigoTipoVeiculo),
    marcas = unique(plano$codigoMarca)
  )
  if (nrow(existentes) == 0) return(plano)
  chaves <- intersect(fipe_prices_keys(), names(plano))
  dplyr::anti_join(plano, existentes, by = chaves)
}

#' Grava precos no layout achatado, deduplicando pela chave natural.
#'
#' Read-modify-write: le as particoes tocadas, junta com as novas linhas,
#' aplica `distinct()` na chave e regrava CADA particao tocada como um unico
#' parquet compactado (`delete_matching` so apaga as particoes que serao
#' reescritas, preservando as demais marcas).
#'
#' @return numero de linhas efetivamente novas adicionadas.
#' @noRd
fipe_write_prices <- function(df, data_dir = "data") {
  if (is.null(df) || nrow(df) == 0) return(invisible(0L))
  path <- file.path(data_dir, "prices")
  chaves <- fipe_prices_keys()

  particoes <- dplyr::distinct(df, .data$codigoTipoVeiculo, .data$codigoMarca)
  existentes <- fipe_prices_full_particoes(data_dir, particoes)
  if (is.null(existentes)) existentes <- df[0, , drop = FALSE]
  antes <- nrow(existentes)

  combinado <- dplyr::bind_rows(existentes, df) |>
    dplyr::distinct(dplyr::across(dplyr::all_of(chaves)), .keep_all = TRUE)

  arrow::write_dataset(
    combinado,
    path = path,
    partitioning = fipe_prices_partition(),
    format = "parquet",
    existing_data_behavior = "delete_matching"
  )
  invisible(nrow(combinado) - antes)
}

#' Baixa precos para um conjunto de combinacoes carro x tabela de referencia.
#'
#' Iterador com callback de progresso. Antes de baixar, descarta o que ja
#' existe em disco (sem bater na API). Acumula as linhas num buffer e descarrega
#' a cada `flush_every` itens (durabilidade) e ao final.
#'
#' @param plano data.frame com colunas codigoTipoVeiculo, codigoMarca,
#'   codigoModelo, anoModelo, codigoTipoCombustivel, codigoTabelaReferencia.
#' @param data_dir diretorio raiz dos dados.
#' @param on_progress funcao(i, n, linha) chamada a cada iteracao.
#' @param flush_every grava em disco a cada N linhas baixadas.
#' @return numero de series novas baixadas.
#' @noRd
baixar_precos_em_lote <- function(plano, data_dir = "data", on_progress = NULL,
                                  flush_every = 25L) {
  plano <- fipe_filtrar_plano_novo(plano, data_dir)
  n <- nrow(plano)
  if (n == 0) return(invisible(0L))

  buffer <- list()
  baixados <- 0L
  flush <- function() {
    if (length(buffer) == 0) return(invisible())
    fipe_write_prices(dplyr::bind_rows(buffer), data_dir)
    buffer <<- list()
  }

  for (i in seq_len(n)) {
    linha <- plano[i, ]
    res <- fetchPrice_safe(
      codigoTipoVeiculo = linha$codigoTipoVeiculo,
      codigoMarca = linha$codigoMarca,
      codigoModelo = linha$codigoModelo,
      anoModelo = linha$anoModelo,
      codigoTipoCombustivel = linha$codigoTipoCombustivel,
      codigoTabelaReferencia = linha$codigoTabelaReferencia
    )
    if (!is.null(res)) {
      buffer[[length(buffer) + 1L]] <- res
      baixados <- baixados + 1L
    }
    if (length(buffer) >= flush_every) flush()
    if (is.function(on_progress)) on_progress(i, n, linha)
  }
  flush()
  invisible(baixados)
}

#' Migra o dataset de precos do layout antigo (6 niveis) para o achatado.
#'
#' `arrow::open_dataset` reconstroi as colunas a partir dos nomes das pastas
#' antigas, entao basta reescrever com a nova particao. Nao apaga o original:
#' grava em `dest_dir` para permitir comparacao/validacao antes do swap.
#' @noRd
fipe_migrar_prices_layout <- function(data_dir = "data",
                                      dest_dir = file.path(data_dir, "_prices_flat")) {
  src <- file.path(data_dir, "prices")
  if (!dir.exists(src)) stop("Nao ha prices/ em ", data_dir)
  df <- arrow::open_dataset(src) |> dplyr::collect() |> fipe_coerce_keys()
  arrow::write_dataset(
    df,
    path = file.path(dest_dir, "prices"),
    partitioning = fipe_prices_partition(),
    format = "parquet",
    existing_data_behavior = "delete_matching"
  )
  invisible(nrow(df))
}
