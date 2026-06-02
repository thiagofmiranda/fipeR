# ============================================================
# Modulo: Visualizacao de precos
# ============================================================

#' UI do modulo de visualizacao.
#' @noRd
mod_visualizacao_ui <- function(id) {
  ns <- NS(id)

  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 380,
      title = tags$span(bsicon("sliders"), "Filtros"),
      open = TRUE,

      shinyWidgets::pickerInput(
        ns("marca"), "Marca",
        choices = NULL, multiple = TRUE,
        options = shinyWidgets::pickerOptions(
          liveSearch = TRUE, actionsBox = TRUE,
          noneSelectedText = "Selecione...",
          selectedTextFormat = "count > 1",
          countSelectedText = "{0} marcas"
        )
      ),
      shinyWidgets::pickerInput(
        ns("modelo"), "Modelo",
        choices = NULL, multiple = TRUE,
        options = shinyWidgets::pickerOptions(
          liveSearch = TRUE, actionsBox = TRUE,
          noneSelectedText = "Selecione uma marca",
          selectedTextFormat = "count > 2",
          countSelectedText = "{0} modelos"
        )
      ),
      shinyWidgets::pickerInput(
        ns("ano_modelo"), "Ano do modelo",
        choices = NULL, multiple = TRUE,
        options = shinyWidgets::pickerOptions(
          actionsBox = TRUE, noneSelectedText = "Todos",
          selectedTextFormat = "count > 3",
          countSelectedText = "{0} anos"
        )
      ),
      sliderInput(
        ns("ano_ref"), "Ano de referencia (FIPE)",
        min = 2000, max = 2030, value = c(2000, 2030),
        step = 1, sep = ""
      ),
      # Contador compacto de series selecionadas (substitui o value box).
      div(
        class = "fipe-series-count",
        bsicon("collection"),
        tags$span(class = "fipe-series-label", "Series selecionadas"),
        tags$span(class = "fipe-series-value", textOutput(ns("kpi_series"), inline = TRUE))
      ),
      div(
        class = "d-grid gap-2 mt-2",
        actionButton(ns("limpar"), "Limpar filtros",
                     class = "btn-outline-secondary btn-sm",
                     icon = icon("eraser"))
      )
    ),

    bslib::card(
      full_screen = TRUE,
      bslib::card_header(
        class = "d-flex justify-content-between align-items-center",
        tags$span(bsicon("graph-up"), "Evolucao do preco"),
        shinyWidgets::prettySwitch(
          ns("log_y"), "Escala log", status = "primary",
          fill = TRUE, inline = TRUE
        )
      ),
      echarts4r::echarts4rOutput(ns("grafico"), height = "440px")
    ),

    bslib::card(
      full_screen = TRUE,
      bslib::card_header(tags$span(bsicon("table"), "Dados filtrados")),
      reactable::reactableOutput(ns("tabela"))
    )
  )
}

#' Server do modulo de visualizacao.
#' @param dados reactive() retornando o tibble de precos tratado.
#' @noRd
mod_visualizacao_server <- function(id, dados) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Opcoes de ano-modelo ordenadas por anoOrdem (0km sempre por ultimo).
    anos_ordenados <- function(df_sel) {
      df_sel |>
        dplyr::distinct(.data$anoModeloLabel, .data$anoOrdem) |>
        dplyr::arrange(.data$anoOrdem) |>
        dplyr::pull(.data$anoModeloLabel)
    }

    # --- (Re)popular filtros sempre que os dados mudam ------------
    # Dispara na carga inicial e tambem apos um download, mantendo a
    # selecao atual do usuario (so descarta o que deixou de existir).
    primeira_carga <- reactiveVal(TRUE)

    observeEvent(dados(), {
      df <- dados()
      if (nrow(df) == 0) return()

      # Marca: todas as opcoes, preservando o que ja estava selecionado.
      marcas <- sort(unique(df$marca))
      sel_marca <- intersect(input$marca, marcas)
      shinyWidgets::updatePickerInput(
        session, "marca", choices = marcas, selected = sel_marca
      )

      # Modelo: depende da marca selecionada; preserva selecao valida.
      modelos <- if (length(sel_marca) == 0) {
        character(0)
      } else {
        df |>
          dplyr::filter(.data$marca %in% sel_marca) |>
          dplyr::pull(.data$modelo) |> unique() |> sort()
      }
      sel_modelo <- intersect(input$modelo, modelos)
      shinyWidgets::updatePickerInput(
        session, "modelo", choices = modelos, selected = sel_modelo
      )

      # Ano-modelo: depende de marca + modelo; preserva selecao valida.
      sel <- df
      if (length(sel_marca) > 0)  sel <- dplyr::filter(sel, .data$marca %in% sel_marca)
      if (length(sel_modelo) > 0) sel <- dplyr::filter(sel, .data$modelo %in% sel_modelo)
      anos <- anos_ordenados(sel)
      shinyWidgets::updatePickerInput(
        session, "ano_modelo", choices = anos,
        selected = intersect(input$ano_modelo, anos)
      )

      # Slider de ano de referencia: amplia os limites; mantem o intervalo
      # escolhido (clampado) ou usa o range completo na primeira carga.
      anos_ref <- range(df$anoReferencia, na.rm = TRUE)
      valor_ref <- if (isTRUE(primeira_carga()) || is.null(input$ano_ref)) {
        anos_ref
      } else {
        c(max(input$ano_ref[1], anos_ref[1]), min(input$ano_ref[2], anos_ref[2]))
      }
      updateSliderInput(
        session, "ano_ref",
        min = anos_ref[1], max = anos_ref[2], value = valor_ref
      )

      primeira_carga(FALSE)
    })

    # --- Modelos dependentes da marca -----------------------------
    observeEvent(input$marca, ignoreNULL = FALSE, {
      df <- dados()
      modelos <- if (length(input$marca) == 0) {
        character(0)
      } else {
        df |>
          dplyr::filter(.data$marca %in% input$marca) |>
          dplyr::pull(.data$modelo) |>
          unique() |>
          sort()
      }
      shinyWidgets::updatePickerInput(session, "modelo", choices = modelos)
    })

    # --- Anos-modelo dependentes do modelo ------------------------
    observeEvent(list(input$marca, input$modelo), ignoreNULL = FALSE, {
      df <- dados()
      sel <- df
      if (length(input$marca) > 0) sel <- dplyr::filter(sel, .data$marca %in% input$marca)
      if (length(input$modelo) > 0) sel <- dplyr::filter(sel, .data$modelo %in% input$modelo)
      shinyWidgets::updatePickerInput(session, "ano_modelo", choices = anos_ordenados(sel))
    })

    observeEvent(input$limpar, {
      shinyWidgets::updatePickerInput(session, "modelo", selected = character(0))
      shinyWidgets::updatePickerInput(session, "ano_modelo", selected = character(0))
      shinyWidgets::updatePickerInput(session, "marca", selected = character(0))
    })

    # --- Dataset filtrado -----------------------------------------
    filtrado <- reactive({
      df <- dados()
      if (nrow(df) == 0) return(df)

      if (length(input$marca) > 0)      df <- dplyr::filter(df, .data$marca %in% input$marca)
      if (length(input$modelo) > 0)     df <- dplyr::filter(df, .data$modelo %in% input$modelo)
      if (length(input$ano_modelo) > 0) df <- dplyr::filter(df, .data$anoModeloLabel %in% input$ano_modelo)
      if (!is.null(input$ano_ref)) {
        df <- dplyr::filter(df,
          .data$anoReferencia >= input$ano_ref[1],
          .data$anoReferencia <= input$ano_ref[2]
        )
      }
      df
    })

    # --- Contador de series selecionadas (sidebar) ----------------
    output$kpi_series <- renderText({
      df <- filtrado()
      as.character(dplyr::n_distinct(df$serie))
    })

    # --- Grafico ---------------------------------------------------
    output$grafico <- echarts4r::renderEcharts4r({
      df <- filtrado()
      validate(need(nrow(df) > 0, "Selecione ao menos uma marca/modelo para visualizar."))

      plot_df <- df |>
        dplyr::group_by(.data$serie, .data$data) |>
        dplyr::summarise(valor = mean(.data$valor, na.rm = TRUE), .groups = "drop") |>
        dplyr::arrange(.data$data)

      e <- plot_df |>
        dplyr::group_by(.data$serie) |>
        echarts4r::e_charts(data) |>
        echarts4r::e_line(valor, smooth = FALSE, symbol = "none", lineStyle = list(width = 2.5)) |>
        echarts4r::e_tooltip(
          trigger = "axis",
          formatter = echarts4r::e_tooltip_pointer_formatter("currency")
        ) |>
        echarts4r::e_legend(type = "scroll", top = 0) |>
        echarts4r::e_grid(top = 56, left = 70, right = 24, bottom = 36) |>
        echarts4r::e_x_axis(type = "time") |>
        echarts4r::e_y_axis(
          type = if (isTRUE(input$log_y)) "log" else "value",
          axisLabel = list(formatter = "R$ {value}")
        ) |>
        echarts4r::e_datazoom(type = "slider", bottom = 0) |>
        echarts4r::e_color(pal_fipe(dplyr::n_distinct(plot_df$serie)))

      e
    })

    # --- Tabela ----------------------------------------------------
    output$tabela <- reactable::renderReactable({
      df <- filtrado()
      validate(need(nrow(df) > 0, "Sem dados."))

      tab <- df |>
        dplyr::transmute(
          Marca = .data$marca,
          Modelo = .data$modelo,
          `Ano modelo` = .data$anoModeloLabel,
          Origem = ifelse(.data$origem_0km, "0 km", "FIPE"),
          Referencia = format(.data$data, "%m/%Y"),
          Combustivel = .data$combustivel,
          Valor = .data$valor
        ) |>
        dplyr::arrange(.data$Marca, .data$Modelo, .data$Referencia)

      reactable::reactable(
        tab,
        searchable = TRUE, striped = TRUE, highlight = TRUE,
        compact = TRUE, defaultPageSize = 12,
        columns = list(
          Valor = reactable::colDef(
            format = reactable::colFormat(prefix = "R$ ", separators = TRUE, digits = 2),
            align = "right"
          )
        )
      )
    })
  })
}
