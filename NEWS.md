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
