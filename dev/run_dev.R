# Carrega o pacote e roda a app em modo de desenvolvimento.
# Uso (a partir da raiz do projeto):  source("dev/run_dev.R")

options(golem.app.prod = FALSE)
Sys.setenv("GOLEM_CONFIG_ACTIVE" = "dev")

# Carrega todas as funcoes do pacote sem instalar.
pkgload::load_all(".", export_all = FALSE, helpers = FALSE, attach_testthat = FALSE)

# data_dir aponta para os parquets na raiz do projeto.
run_app(data_dir = "data")
