# fipeR — Dashboard FIPE

Aplicação Shiny (estruturada com [golem](https://thinkr-open.github.io/golem/)) para
**orquestrar o download** da Tabela FIPE e **visualizar a evolução de preços** de
veículos por marca, modelo, ano-modelo e ano de referência.

Os dados ficam em `data/` como **parquet particionado** (via `arrow`):

```
data/models   modelo  ->  codigoTipoVeiculo / codigoTabelaReferencia / codigoMarca
data/cars     anos/combustível por modelo
data/prices   valor por carro x mês de referência (base da visualização)
```

## Estrutura

```
R/
  run_app.R          run_app() — ponto de entrada
  app_ui.R           navbar bslib + tema minimalista
  app_server.R       carrega os preços 1x e religa após download
  mod_visualizacao.R aba "Preços": filtros + gráfico echarts4r + tabela
  mod_download.R     aba "Download": orquestra a API FIPE e grava parquet
  fct_fipe_api.R     camada de API (httr2)  — fipe_api()
  fct_download.R     downloadModels/Cars/Prices + download em lote
  fct_data.R         leitura/tratamento dos parquets — fipe_load_prices()
  utils_helpers.R    formatação BRL, paleta, ícones
inst/
  golem-config.yml   config (data_dir, prod/dev)
  app/www/custom.css  estilo
dev/run_dev.R        roda em modo desenvolvimento
```

## As duas funções (conforme pedido)

1. **Download de arquivos** — aba *Download*. Fluxo guiado:
   tabela de referência → marca → `1. Baixar modelos` → modelo →
   `2. Carregar anos/versões` → seleciona versões + intervalo de meses →
   `3. Baixar histórico de preços`. Idempotente (pula o que já existe),
   com log e barra de progresso.
2. **Visualização de preço** — aba *Preços*. Filtros de **marca, modelo,
   ano-modelo e ano de referência**; gráfico de linhas interativo
   (echarts4r, zoom + escala log opcional), KPIs e tabela filtrável.

## Rodar localmente (dev)

```r
# a partir da raiz do projeto
source("dev/run_dev.R")
```

## Rodar / instalar (produção, ex.: VPS)

```r
# 1) instalar dependências
install.packages(c(
  "golem","shiny","bslib","bsicons","echarts4r","arrow","dplyr","tidyr",
  "stringr","shinyWidgets","reactable","waiter","config","purrr","lubridate",
  "htmltools","scales","httr2","jsonlite","rlang"
))

# 2) instalar o pacote e rodar
# install.packages(".", repos = NULL, type = "source")
fipeR::run_app(
  data_dir = "data",
  options = list(host = "0.0.0.0", port = 3838)
)
```

Atrás de um proxy (nginx) basta expor a porta 3838. O `data_dir` pode apontar
para um volume persistente com os parquets.

## Implantação

A implantação em container/ShinyProxy é feita posteriormente, no próprio
ambiente do ShinyProxy — o `Dockerfile` e a configuração de orquestração são
criados lá. O app só precisa escutar em `0.0.0.0:3838` e ler/gravar os parquets
no diretório apontado por `FIPE_DATA_DIR` (ou pelo argumento `data_dir`).
