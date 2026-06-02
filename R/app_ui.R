#' UI principal da aplicacao
#' @param request Internal parameter for `{shiny}`.
#' @noRd
app_ui <- function(request) {
  tagList(
    golem_add_external_resources(),
    bslib::page_navbar(
      title = tags$span(
        class = "fipe-brand",
        bsicon("speedometer2"), tags$strong(" FIPE"), tags$span(" Dashboard")
      ),
      id = "nav",
      theme = fipe_theme(),
      window_title = "FIPE Dashboard",
      # fillable = FALSE: o conteudo mantem sua altura natural e a pagina rola
      # verticalmente. Com fillable = TRUE os KPIs + cards disputavam a altura
      # da viewport e o grafico quase sumia em telas menores.
      fillable = FALSE,

      bslib::nav_panel(
        title = "Precos",
        icon = bsicon("graph-up"),
        mod_visualizacao_ui("viz")
      ),
      bslib::nav_panel(
        title = "Download",
        icon = bsicon("cloud-arrow-down"),
        mod_download_ui("download")
      ),
      bslib::nav_spacer(),
      bslib::nav_item(
        tags$a(
          class = "nav-link", href = "https://veiculos.fipe.org.br",
          target = "_blank", bsicon("box-arrow-up-right"), " Fonte FIPE"
        )
      )
    )
  )
}

#' Tema bslib minimalista do dashboard.
#' @noRd
fipe_theme <- function() {
  bslib::bs_theme(
    version = 5,
    primary = "#2563eb",
    success = "#16a34a",
    info = "#0891b2",
    base_font = bslib::font_google("Inter", local = FALSE),
    heading_font = bslib::font_google("Inter", local = FALSE),
    "navbar-bg" = "#0f172a",
    "border-radius" = "0.75rem"
  )
}

#' Recursos externos (CSS/JS/favicon) + dependencias de pacotes.
#' @noRd
golem_add_external_resources <- function() {
  add_resource_path("www", app_sys("app/www"))

  tags$head(
    tags$link(rel = "icon", type = "image/png", href = "www/favicon.png"),
    tags$title("FIPE Dashboard"),
    tags$link(rel = "stylesheet", type = "text/css", href = "www/custom.css"),
    waiter::useWaiter()
  )
}

#' Registra um caminho de recurso estatico de forma defensiva.
#' @noRd
add_resource_path <- function(prefix, directoryPath) {
  if (!is.null(directoryPath) && dir.exists(directoryPath)) {
    shiny::addResourcePath(prefix, directoryPath)
  }
}
