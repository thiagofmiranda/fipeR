#' Run the FIPE Shiny Application
#'
#' @param data_dir Diretorio raiz dos datasets parquet (`data/prices`,
#'   `data/cars`, `data/models`). Por padrao usa o valor do golem-config.
#' @param onStart,options,enableBookmarking,uiPattern argumentos repassados
#'   para [shiny::shinyApp()].
#' @param ... argumentos nomeados extras disponiveis em `golem::get_golem_options()`.
#'
#' @export
#' @importFrom shiny shinyApp
run_app <- function(data_dir = NULL,
                    onStart = NULL,
                    options = list(),
                    enableBookmarking = NULL,
                    uiPattern = "/",
                    ...) {
  if (is.null(data_dir)) {
    # Precedencia: env var (container) > golem-config > padrao "data".
    env_dir <- Sys.getenv("FIPE_DATA_DIR", unset = "")
    if (nzchar(env_dir)) {
      data_dir <- env_dir
    } else {
      data_dir <- get_golem_config("data_dir")
      if (is.null(data_dir)) data_dir <- "data"
    }
  }

  with_golem_options(
    app = shinyApp(
      ui = app_ui,
      server = app_server,
      onStart = onStart,
      options = options,
      enableBookmarking = enableBookmarking,
      uiPattern = uiPattern
    ),
    golem_opts = list(data_dir = data_dir, ...)
  )
}

#' Minimal shim para with_golem_options/get_golem_options
#'
#' Mantem a app funcional mesmo sem carregar todo o golem em runtime.
#' @noRd
with_golem_options <- function(app, golem_opts) {
  options("golem_options" = golem_opts)
  app
}

#' @noRd
get_golem_options <- function(which = NULL) {
  opts <- getOption("golem_options", default = list())
  if (is.null(which)) opts else opts[[which]]
}
