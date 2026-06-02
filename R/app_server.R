#' Server principal da aplicacao
#' @param input,output,session Internal parameters for `{shiny}`.
#' @noRd
app_server <- function(input, output, session) {
  data_dir <- get_golem_options("data_dir")
  if (is.null(data_dir)) data_dir <- "data"

  # Carrega os precos uma vez; recarrega quando o modulo de download avisa.
  dados <- reactiveVal(NULL)

  carregar <- function() {
    w <- waiter::Waiter$new(
      html = tagList(waiter::spin_3(), tags$br(), "Carregando dados FIPE..."),
      color = "rgba(15,23,42,0.85)"
    )
    w$show()
    on.exit(w$hide())
    dados(fipe_load_prices(data_dir))
  }

  carregar()

  # Modulo de download devolve um trigger; ao mudar, recarrega os precos.
  precos_trigger <- mod_download_server("download", data_dir = data_dir)

  observeEvent(precos_trigger(), ignoreInit = TRUE, {
    carregar()
  })

  # Visualizacao consome os dados ja tratados.
  mod_visualizacao_server("viz", dados = dados)
}
