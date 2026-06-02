# ============================================================
# Camada de acesso a API da Tabela FIPE (veiculos.fipe.org.br)
# Portado de consulta_post.R + main.R, encapsulado como funcoes do pacote.
# ============================================================

#' Requisicao POST generica (httr2)
#'
#' @param url URL do endpoint.
#' @param body Lista nomeada com os dados a enviar.
#' @param formato "json" ou "form".
#' @param headers Lista nomeada de cabecalhos extras.
#' @param parse Se TRUE, converte a resposta JSON em objeto R.
#' @noRd
post_request <- function(url,
                         body = list(),
                         formato = c("json", "form"),
                         headers = list(),
                         parse = TRUE) {
  formato <- match.arg(formato)

  req <- httr2::request(url) |>
    httr2::req_method("POST") |>
    httr2::req_retry(max_tries = 3) |>
    httr2::req_error(is_error = function(resp) FALSE)

  if (length(headers) > 0) {
    req <- req |> httr2::req_headers(!!!headers)
  }

  req <- switch(formato,
    json = req |> httr2::req_body_json(body),
    form = req |> httr2::req_body_form(!!!body)
  )

  resp <- httr2::req_perform(req)

  status <- httr2::resp_status(resp)
  if (status >= 400) {
    stop(sprintf("Erro HTTP %d: %s", status, httr2::resp_body_string(resp)))
  }

  if (parse && grepl("application/json", httr2::resp_content_type(resp))) {
    httr2::resp_body_json(resp, simplifyVector = TRUE)
  } else if (parse) {
    httr2::resp_body_string(resp)
  } else {
    resp
  }
}

#' Centraliza rate-limiting + retry com backoff progressivo.
#' @noRd
post_fipe <- function(url, body, formato = "json", tentativas = 3, espera = 2) {
  for (i in seq_len(tentativas)) {
    resposta <- tryCatch(
      post_request(url = url, body = body, formato = formato),
      error = function(e) e
    )
    if (!inherits(resposta, "error")) {
      Sys.sleep(espera)
      return(resposta)
    }
    message("Tentativa ", i, "/", tentativas, " falhou: ", conditionMessage(resposta))
    Sys.sleep(espera * i)
  }
  stop("Falha apos ", tentativas, " tentativas em ", url)
}

#' Forca chaves numericas para inteiro de forma consistente.
#' @noRd
as_int <- function(x) as.integer(as.character(x))

# ------------------------------------------------------------
# Funcoes de consulta
# ------------------------------------------------------------

#' Lista as tabelas de referencia (Codigo + Mes/ano).
#' @noRd
consultarTabelaReferencia <- function() {
  url <- "https://veiculos.fipe.org.br/api/veiculos/ConsultarTabelaDeReferencia"
  resposta <- post_fipe(url, body = list())
  resposta |>
    dplyr::rename(codigoTabelaReferencia = "Codigo", mesReferencia = "Mes") |>
    dplyr::mutate(codigoTabelaReferencia = as_int(.data$codigoTabelaReferencia))
}

#' @noRd
consultarMarcas <- function(codigoTabelaReferencia = 333, codigoTipoVeiculo = 1) {
  url <- "https://veiculos.fipe.org.br/api/veiculos/ConsultarMarcas"
  body <- list(
    codigoTipoVeiculo = codigoTipoVeiculo,
    codigoTabelaReferencia = codigoTabelaReferencia
  )
  resposta <- post_fipe(url, body)
  dplyr::bind_cols(body, resposta) |>
    dplyr::rename(marca = "Label", codigoMarca = "Value") |>
    dplyr::mutate(dplyr::across(
      c("codigoTipoVeiculo", "codigoTabelaReferencia", "codigoMarca"), as_int
    ))
}

#' @noRd
consultarModelos <- function(codigoTabelaReferencia = 333, codigoMarca = 6,
                             codigoTipoVeiculo = 1) {
  url <- "https://veiculos.fipe.org.br/api/veiculos/ConsultarModelos"
  body <- list(
    codigoTipoVeiculo = codigoTipoVeiculo,
    codigoTabelaReferencia = codigoTabelaReferencia,
    codigoMarca = codigoMarca
  )
  resposta <- post_fipe(url, body)
  dplyr::bind_cols(body, resposta$Modelos) |>
    dplyr::rename(modelo = "Label", codigoModelo = "Value") |>
    dplyr::mutate(dplyr::across(
      c("codigoTipoVeiculo", "codigoTabelaReferencia", "codigoMarca", "codigoModelo"),
      as_int
    ))
}

#' @noRd
consultarAnoModelo <- function(codigoMarca = 6, codigoModelo = 5496,
                               codigoTabelaReferencia = 333, codigoTipoVeiculo = 1) {
  url <- "https://veiculos.fipe.org.br/api/veiculos/ConsultarAnoModelo"
  body <- list(
    codigoTipoVeiculo = codigoTipoVeiculo,
    codigoTabelaReferencia = codigoTabelaReferencia,
    codigoModelo = codigoModelo,
    codigoMarca = codigoMarca
  )
  resposta <- post_fipe(url, body)
  dplyr::bind_cols(body, resposta)
}

#' @noRd
consultarValorComTodosParametros <- function(codigoMarca = 6, codigoModelo = 5496,
                                             anoModelo = 2014, codigoTipoCombustivel = 1,
                                             codigoTabelaReferencia = 333,
                                             codigoTipoVeiculo = 1) {
  url <- "https://veiculos.fipe.org.br/api/veiculos/ConsultarValorComTodosParametros"
  tipoVeiculo <- c("1" = "carro", "2" = "moto", "3" = "caminhao")[as.character(codigoTipoVeiculo)]

  body <- list(
    codigoTipoVeiculo = codigoTipoVeiculo,
    tipoVeiculo = unname(tipoVeiculo),
    codigoTabelaReferencia = codigoTabelaReferencia,
    codigoModelo = codigoModelo,
    codigoMarca = codigoMarca,
    codigoTipoCombustivel = codigoTipoCombustivel,
    anoModelo = anoModelo,
    tipoConsulta = "tradicional"
  )
  resposta <- post_fipe(url, body)

  res <- data.frame(
    valorCarro = resposta$Valor,
    marca = resposta$Marca,
    modelo = resposta$Modelo,
    combustivel = resposta$Combustivel,
    siglaCombustivel = resposta$SiglaCombustivel,
    codigoFipe = resposta$CodigoFipe,
    mesReferencia = resposta$MesReferencia,
    data_consulta = resposta$DataConsulta
  )

  dplyr::bind_cols(body, res) |>
    dplyr::mutate(dplyr::across(
      c("codigoTipoVeiculo", "codigoTabelaReferencia", "codigoModelo",
        "codigoMarca", "codigoTipoCombustivel", "anoModelo"), as_int
    ))
}

#' Fachada publica das consultas FIPE.
#'
#' Permite chamar `fipe_api("marcas", ...)` etc. de forma estavel.
#' @param what Uma de "tabelas", "marcas", "modelos", "anos", "valor".
#' @param ... argumentos repassados a funcao subjacente.
#' @export
fipe_api <- function(what = c("tabelas", "marcas", "modelos", "anos", "valor"), ...) {
  what <- match.arg(what)
  switch(what,
    tabelas = consultarTabelaReferencia(),
    marcas = consultarMarcas(...),
    modelos = consultarModelos(...),
    anos = consultarAnoModelo(...),
    valor = consultarValorComTodosParametros(...)
  )
}
