# ============================================================
# Modulo: Download / orquestracao da Tabela FIPE
# ============================================================

#' UI do modulo de download.
#' @noRd
mod_download_ui <- function(id) {
  ns <- NS(id)

  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 380,
      title = tags$span(bsicon("cloud-arrow-down"), "Orquestrar download"),
      open = TRUE,

      tags$p(
        class = "text-muted small",
        "Os dados sao baixados da API publica da Tabela FIPE e gravados em ",
        tags$code("data/"), " como parquet particionado."
      ),

      shinyWidgets::pickerInput(
        ns("tabela"), "Tabela de referencia (mes-base)",
        choices = NULL,
        options = shinyWidgets::pickerOptions(liveSearch = TRUE)
      ),
      shinyWidgets::pickerInput(
        ns("marca"), "Marca",
        choices = NULL,
        options = shinyWidgets::pickerOptions(
          liveSearch = TRUE, noneSelectedText = "Carregando..."
        )
      ),
      div(
        class = "d-grid gap-2",
        actionButton(ns("get_modelos"), "1. Baixar modelos da marca",
                     class = "btn-primary btn-sm", icon = icon("car-side"))
      ),
      shinyWidgets::pickerInput(
        ns("modelo"), "Modelo",
        choices = NULL,
        options = shinyWidgets::pickerOptions(
          liveSearch = TRUE, noneSelectedText = "Baixe os modelos primeiro"
        )
      ),
      div(
        class = "d-grid gap-2",
        actionButton(ns("get_anos"), "2. Carregar anos / versoes",
                     class = "btn-primary btn-sm", icon = icon("calendar"))
      ),
      tags$hr(),
      tags$strong(class = "small text-uppercase text-muted", "Historico de precos"),
      shinyWidgets::pickerInput(
        ns("versoes"), "Versoes (ano-modelo / combustivel)",
        choices = NULL, multiple = TRUE,
        options = shinyWidgets::pickerOptions(
          actionsBox = TRUE, liveSearch = TRUE,
          noneSelectedText = "Carregue os anos"
        )
      ),
      shinyWidgets::pickerInput(
        ns("tabela_de"), "De (mes-base)",
        choices = NULL, options = shinyWidgets::pickerOptions(liveSearch = TRUE)
      ),
      shinyWidgets::pickerInput(
        ns("tabela_ate"), "Ate (mes-base)",
        choices = NULL, options = shinyWidgets::pickerOptions(liveSearch = TRUE)
      ),
      div(
        class = "d-grid gap-2 mt-2",
        conditionalPanel(
          condition = "!output.rodando", ns = ns,
          actionButton(ns("get_precos"), "3. Baixar historico de precos",
                       class = "btn-success", icon = icon("download"))
        ),
        conditionalPanel(
          condition = "output.rodando", ns = ns,
          actionButton(ns("cancelar"), "Cancelar download",
                       class = "btn-danger", icon = icon("stop"))
        )
      ),
      conditionalPanel(
        condition = "output.rodando", ns = ns,
        div(
          class = "mt-2",
          shinyWidgets::progressBar(
            ns("pb"), value = 0, total = 100,
            display_pct = TRUE, status = "success"
          )
        )
      )
    ),

    bslib::layout_columns(
      fill = FALSE,
      bslib::value_box(
        title = "Marcas no catalogo",
        value = textOutput(ns("kpi_marcas")),
        showcase = bsicon("tags"), theme = "secondary"
      ),
      bslib::value_box(
        title = "Modelos baixados",
        value = textOutput(ns("kpi_modelos")),
        showcase = bsicon("car-front"), theme = "secondary"
      ),
      bslib::value_box(
        title = "Series de preco gravadas",
        value = textOutput(ns("kpi_precos")),
        showcase = bsicon("database-check"), theme = "secondary"
      )
    ),

    bslib::card(
      bslib::card_header(tags$span(bsicon("terminal"), "Log de execucao")),
      bslib::card_body(
        min_height = 220,
        verbatimTextOutput(ns("log"))
      )
    )
  )
}

#' Server do modulo de download.
#'
#' @param data_dir diretorio raiz dos dados.
#' @return reactive (contador) que incrementa apos baixar precos, para o
#'   app recarregar a visualizacao.
#' @noRd
mod_download_server <- function(id, data_dir = "data") {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    rv <- reactiveValues(
      tabelas = NULL,    # data.frame Codigo/Mes
      cars = NULL,       # df de anos/versoes do modelo selecionado
      log = character(0),
      precos_trigger = 0L,
      catalogo_trigger = 0L,
      # Estado do download de precos (processado 1 item por "tick").
      fila = NULL,       # data.frame com o plano de download
      idx = 0L,          # quantos itens ja processados
      total = 0L,        # tamanho do plano
      baixados = 0L,     # series efetivamente gravadas
      buffer = list(),   # linhas baixadas aguardando flush em disco
      rodando = FALSE,   # ha um download em andamento?
      cancelar = FALSE   # cancelamento solicitado?
    )

    add_log <- function(msg) {
      ts <- format(Sys.time(), "%H:%M:%S")
      rv$log <- c(rv$log, paste0("[", ts, "] ", msg))
    }

    # Descarrega o buffer em disco de forma resiliente: uma falha de gravacao
    # NUNCA pode derrubar o heartbeat (senao o botao Cancelar para de reagir).
    # Em caso de erro, loga e PRESERVA o buffer para retentar no proximo flush.
    flush_buffer <- function() {
      if (length(rv$buffer) == 0) return(invisible())
      ok <- tryCatch({
        fipe_write_prices(dplyr::bind_rows(rv$buffer), data_dir)
        TRUE
      }, error = function(e) {
        add_log(paste("ERRO ao gravar precos (mantendo no buffer):",
                      conditionMessage(e)))
        FALSE
      })
      if (ok) rv$buffer <- list()
      invisible(ok)
    }

    # --- Carrega tabelas de referencia na entrada ------------------
    observeEvent(TRUE, once = TRUE, {
      add_log("Carregando tabelas de referencia da FIPE...")
      tabs <- tryCatch(fipe_api("tabelas"), error = function(e) e)
      if (inherits(tabs, "error")) {
        add_log(paste("ERRO ao carregar tabelas:", conditionMessage(tabs)))
        return()
      }
      rv$tabelas <- tabs
      escolhas <- stats::setNames(tabs$codigoTabelaReferencia,
                                  stringr::str_trim(tabs$mesReferencia))
      # Default do "De": janeiro de 2020 (se existir), senao a tabela mais
      # antiga. O dropdown mantem TODAS as tabelas, entao 2001 continua
      # disponivel para quem quiser o historico completo.
      de_default <- escolhas[grepl("^janeiro/2020$", stringr::str_to_lower(names(escolhas)))]
      if (length(de_default) == 0) de_default <- utils::tail(escolhas, 1)
      shinyWidgets::updatePickerInput(session, "tabela", choices = escolhas)
      shinyWidgets::updatePickerInput(session, "tabela_de", choices = escolhas,
                                      selected = unname(de_default[1]))
      shinyWidgets::updatePickerInput(session, "tabela_ate", choices = escolhas,
                                      selected = escolhas[1])
      add_log(paste0("OK: ", nrow(tabs), " tabelas de referencia."))
    })

    # --- Marcas quando muda a tabela -------------------------------
    observeEvent(input$tabela, {
      req(input$tabela)
      add_log(paste0("Carregando marcas (tabela ", input$tabela, ")..."))
      marcas <- tryCatch(
        fipe_api("marcas", codigoTabelaReferencia = as.integer(input$tabela)),
        error = function(e) e
      )
      if (inherits(marcas, "error")) {
        add_log(paste("ERRO marcas:", conditionMessage(marcas)))
        return()
      }
      escolhas <- stats::setNames(marcas$codigoMarca, marcas$marca)
      shinyWidgets::updatePickerInput(session, "marca", choices = escolhas)
      add_log(paste0("OK: ", nrow(marcas), " marcas."))
    })

    # --- 1. Baixar modelos da marca --------------------------------
    observeEvent(input$get_modelos, {
      req(input$tabela, input$marca)
      tabela <- as.integer(input$tabela)
      marca <- as.integer(input$marca)
      add_log(paste0("Baixando modelos da marca ", marca, "..."))
      withProgress(message = "Baixando modelos...", value = 0.5, {
        res <- tryCatch(
          downloadModels(codigoTipoVeiculo = 1, codigoTabelaReferencia = tabela,
                         codigoMarca = marca, data_dir = data_dir),
          error = function(e) e
        )
      })
      if (inherits(res, "error")) {
        add_log(paste("ERRO modelos:", conditionMessage(res)))
        return()
      }
      escolhas <- stats::setNames(res$codigoModelo, res$modelo)
      shinyWidgets::updatePickerInput(session, "modelo", choices = escolhas)
      rv$catalogo_trigger <- rv$catalogo_trigger + 1L
      add_log(paste0("OK: ", nrow(res), " modelos gravados em data/models."))
    })

    # --- 2. Carregar anos / versoes --------------------------------
    observeEvent(input$get_anos, {
      req(input$tabela, input$marca, input$modelo)
      tabela <- as.integer(input$tabela)
      marca <- as.integer(input$marca)
      modelo <- as.integer(input$modelo)
      add_log(paste0("Carregando anos/versoes do modelo ", modelo, "..."))
      withProgress(message = "Baixando anos...", value = 0.5, {
        res <- tryCatch(
          downloadCars(codigoModelo = modelo, codigoMarca = marca,
                       codigoTabelaReferencia = tabela, codigoTipoVeiculo = 1,
                       data_dir = data_dir),
          error = function(e) e
        )
      })
      if (inherits(res, "error")) {
        add_log(paste("ERRO anos:", conditionMessage(res)))
        return()
      }
      rv$cars <- res
      escolhas <- stats::setNames(
        paste(res$anoModelo, res$codigoTipoCombustivel, sep = "|"),
        paste0(ifelse(res$anoModelo == 32000, "0 km", res$anoModelo),
               " - ", res$tipoCombustivel)
      )
      shinyWidgets::updatePickerInput(session, "versoes", choices = escolhas,
                                      selected = unname(escolhas))
      rv$catalogo_trigger <- rv$catalogo_trigger + 1L
      add_log(paste0("OK: ", nrow(res), " versoes carregadas."))
    })

    # --- 3. Baixar historico de precos (cancelavel) ----------------
    # Em vez de um loop bloqueante, montamos o plano e processamos UM
    # item por "tick" reativo. Entre os ticks o Shiny processa inputs,
    # entao o botao Cancelar e' lido mesmo durante o download.

    # Expoe o estado "rodando" para os conditionalPanel da UI.
    output$rodando <- reactive(isTRUE(rv$rodando))
    outputOptions(output, "rodando", suspendWhenHidden = FALSE)

    observeEvent(input$get_precos, {
      req(input$marca, input$modelo, input$versoes, input$tabela_de, input$tabela_ate)
      if (is.null(rv$tabelas) || isTRUE(rv$rodando)) return()

      marca <- as.integer(input$marca)
      modelo <- as.integer(input$modelo)

      # Intervalo de tabelas de referencia (inclusive).
      cods <- sort(rv$tabelas$codigoTabelaReferencia)
      de <- as.integer(input$tabela_de)
      ate <- as.integer(input$tabela_ate)
      faixa <- cods[cods >= min(de, ate) & cods <= max(de, ate)]

      # Versoes selecionadas -> anoModelo + combustivel.
      versoes <- strsplit(input$versoes, "|", fixed = TRUE)
      versoes_df <- data.frame(
        anoModelo = as.integer(vapply(versoes, `[`, character(1), 1)),
        codigoTipoCombustivel = as.integer(vapply(versoes, `[`, character(1), 2))
      )

      plano <- tidyr::expand_grid(
        codigoTipoVeiculo = 1L,
        codigoMarca = marca,
        codigoModelo = modelo,
        versoes_df,
        codigoTabelaReferencia = faixa
      )

      if (nrow(plano) == 0) {
        add_log("Nada a baixar com os filtros atuais.")
        return()
      }

      # Idempotencia: descarta o que ja esta em disco antes de bater na API.
      total_plano <- nrow(plano)
      plano <- fipe_filtrar_plano_novo(plano, data_dir)
      ja_em_disco <- total_plano - nrow(plano)
      if (nrow(plano) == 0) {
        add_log(paste0("Tudo ja baixado: ", ja_em_disco,
                       " combinacoes ja estao em disco. Nada a fazer."))
        return()
      }

      rv$fila     <- plano
      rv$total    <- nrow(plano)
      rv$idx      <- 0L
      rv$baixados <- 0L
      rv$buffer   <- list()
      rv$cancelar <- FALSE
      rv$rodando  <- TRUE
      shinyWidgets::updateProgressBar(session, "pb", value = 0, total = rv$total)
      add_log(paste0("Iniciando download de precos: ", rv$total, " novas combinacoes",
                     if (ja_em_disco > 0) paste0(" (", ja_em_disco, " ja em disco, puladas)") else "",
                     " (", nrow(versoes_df), " versoes x ", length(faixa), " meses)."))
    })

    # Pedido de cancelamento (so marca a flag; o tick atual termina sozinho).
    observeEvent(input$cancelar, {
      if (isTRUE(rv$rodando) && !isTRUE(rv$cancelar)) {
        rv$cancelar <- TRUE
        add_log("Cancelamento solicitado... aguardando o item atual terminar.")
      }
    })

    # Heartbeat: processa 1 item do plano por tick.
    observe({
      if (!isTRUE(rv$rodando)) return()

      terminou <- isolate(isTRUE(rv$cancelar) || rv$idx >= rv$total)
      if (terminou) {
        isolate({
          rv$rodando <- FALSE
          flush_buffer()  # descarrega o que sobrou antes de encerrar
          motivo <- if (isTRUE(rv$cancelar)) "CANCELADO" else "concluido"
          shinyWidgets::updateProgressBar(session, "pb",
                                          value = rv$idx, total = max(rv$total, 1L))
          add_log(paste0("Download ", motivo, ": ", rv$baixados,
                         " novas series gravadas (", rv$idx, "/", rv$total,
                         " processadas)."))
          rv$precos_trigger   <- rv$precos_trigger + 1L
          rv$catalogo_trigger <- rv$catalogo_trigger + 1L
          showNotification(
            paste0("Download ", motivo, ": ", rv$baixados, " novas series."),
            type = if (isTRUE(rv$cancelar)) "warning" else "message", duration = 5
          )
        })
        return()
      }

      # Ainda ha itens: reagenda o proximo tick e processa o item atual.
      invalidateLater(50)
      isolate({
        i <- rv$idx + 1L
        linha <- rv$fila[i, ]
        res <- fetchPrice_safe(
          codigoTipoVeiculo      = linha$codigoTipoVeiculo,
          codigoMarca            = linha$codigoMarca,
          codigoModelo           = linha$codigoModelo,
          anoModelo              = linha$anoModelo,
          codigoTipoCombustivel  = linha$codigoTipoCombustivel,
          codigoTabelaReferencia = linha$codigoTabelaReferencia
        )
        if (!is.null(res)) {
          rv$buffer[[length(rv$buffer) + 1L]] <- res
          rv$baixados <- rv$baixados + 1L
        }
        rv$idx <- i
        # Flush periodico: durabilidade sem recriar arquivos minusculos.
        if (length(rv$buffer) >= 25L) flush_buffer()
        shinyWidgets::updateProgressBar(session, "pb", value = i, total = rv$total)
      })
    })

    # --- KPIs do catalogo local ------------------------------------
    catalogo_resumo <- reactive({
      rv$catalogo_trigger  # dependencia
      list(
        marcas = contar_particoes(file.path(data_dir, "models"), "codigoMarca"),
        modelos = contar_arquivos(file.path(data_dir, "models")),
        precos = contar_series_precos(data_dir)
      )
    })

    output$kpi_marcas  <- renderText(as.character(catalogo_resumo()$marcas))
    output$kpi_modelos <- renderText(as.character(catalogo_resumo()$modelos))
    output$kpi_precos  <- renderText(as.character(catalogo_resumo()$precos))

    output$log <- renderText({
      if (length(rv$log) == 0) return("Pronto.")
      paste(utils::tail(rv$log, 200), collapse = "\n")
    })

    reactive(rv$precos_trigger)
  })
}

# --- helpers locais de contagem -----------------------------------

#' @noRd
contar_arquivos <- function(path) {
  if (!dir.exists(path)) return(0L)
  length(list.files(path, pattern = "\\.parquet$", recursive = TRUE))
}

#' @noRd
contar_particoes <- function(path, chave) {
  if (!dir.exists(path)) return(0L)
  dirs <- list.dirs(path, recursive = TRUE, full.names = FALSE)
  length(unique(dirs[grepl(paste0("^", chave, "="), basename(dirs))]))
}

#' Conta series de preco distintas (modelo x ano-modelo x combustivel).
#'
#' No layout achatado o numero de arquivos nao reflete mais quantas series
#' existem, entao contamos a chave de serie diretamente do dataset.
#' @noRd
contar_series_precos <- function(data_dir) {
  ex <- fipe_prices_existentes(data_dir)
  if (nrow(ex) == 0) return(0L)
  ex |>
    dplyr::distinct(.data$codigoTipoVeiculo, .data$codigoMarca,
                    .data$codigoModelo, .data$anoModelo,
                    .data$codigoTipoCombustivel) |>
    nrow()
}
