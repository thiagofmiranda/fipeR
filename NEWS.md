# fipeR 0.2.0

## Novidades

* **Layout de dados de precos achatado** (`codigoTipoVeiculo` / `codigoMarca`):
  uma marca inteira passa a viver em um unico parquet por tipo de veiculo, em
  vez de milhares de arquivos minusculos (eram ~1,5 mil so para um modelo). Na
  base atual a leitura ficou ~70x mais rapida (de 1571 para 49 arquivos). A
  gravacao agora e' deduplicada por chave natural (read-modify-write da
  particao tocada). Inclui `fipe_migrar_prices_layout()` para converter dados
  do layout antigo (6 niveis) para o novo.
* **Sem downloads duplicados**: antes de chamar a API, o plano e' filtrado
  contra o que ja existe em disco (anti-join), entao nada que ja foi baixado
  e' baixado de novo.
* **Grafico de evolucao mais simples e bonito**: removida a escala log,
  linhas suaves, eixo Y em R$ abreviado (`R$ 50 mil` / `R$ 1,2 mi`), tooltip
  em reais (`R$ 184.026,00`), eixos discretos e area do grafico mais alta.
* **Intervalo de download** comeca em `janeiro/2020` por padrao (o historico
  completo a partir de 2001 continua selecionavel).

## Correcoes

* O botao **"Cancelar download"** voltava a nao responder quando uma gravacao
  lancava erro: a excecao derrubava o heartbeat e o cancelamento deixava de
  ser lido. Agora a gravacao e' resiliente (erro e' logado, buffer preservado)
  e o cancelamento sempre responde.
* Normaliza o tipo das colunas-chave ao ler do disco: dados legados gravavam
  `codigoTipoCombustivel` como texto, o que quebrava o download com
  "incompatible types" no join.

# fipeR 0.1.1

## Correcoes

* Corrige erro de "estado inicial vazio": com um diretorio de dados vazio ou
  inexistente (ex.: primeira execucao no ShinyProxy), a aba "Precos" quebrava
  com `Error in dplyr::distinct: Must use existing variables`. Agora
  `fipe_load_prices()` retorna um prototipo de 0 linhas com as colunas
  esperadas, e a aba abre vazia com a mensagem amigavel em vez de lancar erro.
  A aba "Download" continua funcionando normalmente, e a visualizacao volta a
  funcionar apos baixar dados.

# fipeR 0.1.0

* Versao inicial: aplicacao Shiny (golem) para orquestrar o download da Tabela
  FIPE e visualizar a evolucao de precos por marca, modelo, ano-modelo e ano de
  referencia, com dados persistidos em parquet particionado (arrow).
