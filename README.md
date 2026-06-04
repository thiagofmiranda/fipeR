# fipeR — Dashboard FIPE

Aplicação Shiny (estruturada com [golem](https://thinkr-open.github.io/golem/)) para
**baixar** dados da Tabela FIPE e **visualizar a evolução de preços** de veículos por
marca, modelo, ano-modelo e ano de referência.

Duas abas:

- **Download** — fluxo guiado: tabela de referência → marca → modelos → anos/versões →
  histórico de preços. Idempotente (pula o que já existe), com log e barra de progresso.
- **Preços** — filtros de marca, modelo, ano-modelo e ano de referência; gráfico de
  linhas interativo (zoom e escala log), KPIs e tabela.

## Instalação

```r
# install.packages("remotes")
remotes::install_github("thiagofmiranda/fipeR")
fipeR::run_app()
```

As dependências são resolvidas automaticamente a partir do `DESCRIPTION`.

## A pasta de dados (obrigatória)

O app **não vem com dados**. Os preços são persistidos como **parquet particionado**
(via `arrow`) num diretório de dados, e a aba *Preços* fica vazia até que algo seja
baixado pela aba *Download*.

Estrutura criada dentro do diretório de dados:

```
prices   valor por carro × mês de referência   (base da visualização)
cars     anos/versões (combustível) por modelo
models   modelos por marca/tabela de referência
```

**Onde fica esse diretório**, em ordem de precedência:

1. `run_app(data_dir = "/caminho")` — argumento explícito;
2. variável de ambiente `FIPE_DATA_DIR` — ideal em container/ShinyProxy (volume montado);
3. padrão: `tools::R_user_dir("fipeR", "data")` — pasta gravável e **persistente** do
   usuário, criada automaticamente.

O diretório precisa ser **gravável** (o download escreve nele) e deve persistir entre
execuções para não perder o histórico baixado.

## Rodar em desenvolvimento

A partir da raiz do projeto (usa os parquets locais em `data/`):

```r
source("dev/run_dev.R")
```

## Rodar em produção

```r
fipeR::run_app(options = list(host = "0.0.0.0", port = 3838))
```

Atrás de um proxy basta expor a porta `3838`.

## Implantação no ShinyProxy

O [ShinyProxy](https://www.shinyproxy.io/) sobe **um container Docker por sessão**. Para
este app são necessárias três peças: a imagem (Dockerfile), a entrada em
`application.yml` e um **volume persistente** para os dados.

### 1. Dockerfile

Instala o pacote a partir do GitHub (as dependências vêm do `DESCRIPTION`) e roda o app
em `0.0.0.0:3838`.

```dockerfile
FROM rocker/r-ver:4.5.1

# Bibliotecas de sistema usadas por arrow, httr2 e afins.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libcurl4-openssl-dev libssl-dev libxml2-dev zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

RUN R -q -e "install.packages('remotes'); \
             remotes::install_github('thiagofmiranda/fipeR@v0.1.1')"

# Diretorio de dados gravavel/persistente (mapeado para um volume no host).
ENV FIPE_DATA_DIR=/data
RUN mkdir -p /data

EXPOSE 3838
CMD ["R", "-e", "fipeR::run_app(options = list(host = '0.0.0.0', port = 3838))"]
```

Construa e publique a imagem (ex.: `docker build -t fiper:latest .`).

### 2. application.yml (ShinyProxy)

Adicione a app em `specs:`. O `container-volumes` monta uma pasta do host no `/data` do
container, e o `port` deve bater com a porta do `run_app()`:

```yaml
specs:
  - id: fiper
    display-name: Dashboard FIPE
    description: Download e visualização de preços da Tabela FIPE
    container-image: fiper:latest
    port: 3838
    container-env:
      FIPE_DATA_DIR: /data
    container-volumes: ["/srv/fiper/data:/data"]
```

### 3. Persistência dos dados

A aba *Preços* só mostra algo depois que dados são baixados pela aba *Download*. Como os
containers do ShinyProxy são efêmeros, **os parquets precisam viver num volume**: o
mapeamento `/srv/fiper/data:/data` acima faz o download gravar em `/data` (apontado por
`FIPE_DATA_DIR`) e persistir no host entre sessões e reinícios.

> Use o **mesmo** caminho de host para todas as sessões se quiser que o histórico baixado
> seja compartilhado entre usuários. Para isolar por usuário, use um subcaminho com
> variáveis do ShinyProxy, ex.: `["/srv/fiper/#{proxy.userId}:/data"]`.

## Estrutura do código

```
R/
  run_app.R          ponto de entrada — run_app()
  app_ui.R           navbar bslib
  app_server.R       carrega os preços e religa após download
  mod_visualizacao.R aba "Preços"
  mod_download.R     aba "Download"
  fct_fipe_api.R     camada de API FIPE (httr2)
  fct_download.R     download de modelos/anos/preços
  fct_data.R         leitura/tratamento dos parquets — fipe_load_prices()
  utils_helpers.R    formatação, paleta, ícones
inst/golem-config.yml  configuração (perfis dev/prod)
```
