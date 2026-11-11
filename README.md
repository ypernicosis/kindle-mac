# kindle-mac

Ferramentas para usar um Kindle com jailbreak e [KOReader](https://koreader.rocks) junto com um Mac:

- **`kindle-enviar`** manda livros do Mac para o Kindle pelo Wi-Fi.
- **`kindle-trechos`** leva os grifos e as notas do KOReader para as notas de livro do [Ateliet](https://github.com/ypernicosis/ateliet) (e do Obsidian, que lê o mesmo vault).
- **`kindle-tela`** transmite a tela do Kindle para o OBS, para fazer lives lendo.
- **`kindle-servir`** atende os botões do plugin **Kindle ↔ Mac** do KOReader, para fazer tudo isso a partir do próprio Kindle, sem SSH.
- **Dicionários em português** montados a partir do Wikcionário, e um script de **ajustes de leitura** para o KOReader.

Testado num Kindle de 11ª geração (kt6), firmware 5.19.4, jailbreak com Jobman e KOReader v2026.07. Só usa a biblioteca padrão do Python 3 no Mac e o `busybox`/`curl` que já vêm no Kindle.

> Livros comprados na Amazon (KFX/AZW com DRM) não abrem no KOReader. Mande para o Kindle os arquivos originais sem DRM (EPUB, PDF, CBZ…).

## Instalação

### No Mac

```sh
git clone https://github.com/ypernicosis/kindle-mac.git ~/Developer/kindle-mac
cd ~/Developer/kindle-mac
mkdir -p ~/.local/bin
ln -sf "$PWD/mac/kindle" ~/.local/bin/kindle
for c in enviar trechos tela servir; do ln -sf kindle ~/.local/bin/kindle-$c; done

# o IP do Kindle na rede (aparece no Jobman ou no KOReader)
mkdir -p ~/.config/kindle && echo 192.168.0.50 > ~/.config/kindle/host
```

`~/.local/bin` precisa estar no `PATH`.

O acesso ao Kindle é por SSH como `root`, pela porta 22 do Jobman. A senha é pedida uma vez a cada comando. Com uma chave em `/mnt/us/.ssh/authorized_keys` no Kindle, a senha deixa de ser pedida.

### No Kindle (plugin do KOReader)

Copie `koreader/kindlemac.koplugin` para `/mnt/us/koreader/plugins/`, por USB ou com:

```sh
tar -C koreader -czf - kindlemac.koplugin | ssh root@KINDLE 'tar -xzf - -C /mnt/us/koreader/plugins'
```

O plugin lê o endereço do Mac e o token em `/mnt/us/koreader/settings/kindlemac.lua`:

```lua
return {
    ["host"] = "192.168.0.10",  -- IP do Mac
    ["porta"] = 8766,
    ["porta_tela"] = 8767,
    ["token"] = "o token de ~/.config/kindle/servidor.json",
    ["fps"] = 3,
}
```

O token é criado na primeira vez que `kindle-servir` roda. O endereço do Mac também pode ser trocado pelo próprio menu do plugin.

### `kindle-servir` sempre ligado

Para os botões funcionarem sem abrir nada no Mac, registre o servidor no `launchd`:

```sh
sed -e "s#KINDLE_BIN#$HOME/.local/bin/kindle#" -e "s#LOG_PATH#$HOME/Library/Logs/kindle-servir.log#" \
    mac/kindle-servir.plist > ~/Library/LaunchAgents/kindle-servir.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/kindle-servir.plist
```

Na primeira conexão, o macOS pode perguntar se o Python pode aceitar conexões da rede. Responda que sim.

## Uso

### Mandar livros

```sh
kindle-enviar livro.epub outro.pdf              # vão para /mnt/us/documents/Livros
kindle-enviar --pasta Quadrinhos revista.cbz    # numa subpasta
kindle-enviar --fila livro.epub                 # só põe na fila
```

Se o Kindle estiver dormindo, os livros ficam na fila em `~/Kindle/Enviar`. Arrastar arquivos para essa pasta pelo Finder também funciona. No Kindle, toque em **Receber livros do Mac** para buscá-los. Os entregues vão para `~/Kindle/Enviados`.

O [Calibre](https://calibre-ebook.com) também funciona. Os livros mandados por ele caem na mesma pasta quando o `inbox_dir` do KOReader aponta para `Livros`, e o `ajustes.lua` não mexe nisso.

### Grifos para o Ateliet

```sh
kindle-trechos            # o vault é o último aberto no Ateliet
kindle-trechos --teste    # mostra o que faria, sem gravar
kindle-trechos --vault ~/caminho/do/vault --sem-livro
```

Cada livro grifado ganha (ou atualiza) uma nota em `Livros/` do vault, no formato do Leitor do Ateliet:

```markdown
> [!grifo|azul] Capítulo 2 · p. 41
> O trecho grifado no Kindle.
>
> Nota: a nota escrita no KOReader.

^g-k1a2b3c
```

Os dados ficam no bloco `%% ateliet:leitor %%` no fim da nota, como faz o Ateliet.

- As cores do KOReader viram as quatro do Ateliet: amarelo, azul, verde e rosa.
- Se o arquivo do livro não estiver no vault, ele é copiado para `Livros/Arquivos/`, para o link "Abrir no Leitor" funcionar. Isso vale para EPUB, PDF e quadrinhos.
- Cada grifo é exportado uma vez só. Os já exportados ficam em `.obsidian/ateliet/kindle-trechos.json`, então um grifo apagado no Obsidian não volta.
- No Ateliet, o grifo aparece na nota e "ir até ele" acha o trecho pelo texto. Ele não fica pintado na página, porque o KOReader e o Ateliet contam posições de jeitos diferentes.

### Tela no OBS

```sh
kindle-tela                  # http://127.0.0.1:8765/
kindle-tela --girar 90       # lendo deitado
kindle-tela --inverter       # modo noturno (a captura não vem invertida)
```

No OBS, adicione em **Fontes → + → Navegador** a URL `http://127.0.0.1:8765/`, com largura 1072 e altura 1448.

O comando lê a tela do Kindle (`/dev/fb0`) umas 3 vezes por segundo, comprimida. Só manda uma imagem nova quando a página muda, e cada página tem uns 50 KB.

Com o `kindle-servir` ligado, o botão **Transmitir a tela para o OBS** do Kindle faz o mesmo sem SSH, na mesma URL.

### Botões no KOReader

Menu 🔧 → **Kindle ↔ Mac**:

| Botão | O que faz |
|---|---|
| Exportar trechos para o Ateliet | O mesmo que `kindle-trechos` |
| Receber livros do Mac | Busca a fila de `~/Kindle/Enviar` |
| Transmitir a tela para o OBS | Liga e desliga a transmissão |
| Abrir o Jobman | Abre o Jobman sobre o KOReader. A seta de voltar do Jobman, ou o botão de ligar, retorna ao KOReader |
| Endereço do Mac / Testar a conexão | Configuração |

Os quatro primeiros também aparecem como ações de gestos (Configurações → Gestos).

O plugin fala com o Mac por HTTP na rede local (porta 8766, e 8767 para a tela). As chamadas sem o token são recusadas. Use só em redes de confiança.

## Dicionários

`dicionarios/montar_wikcionario.py` monta dicionários StarDict a partir da extração do Wikcionário em português feita pelo [kaikki.org](https://kaikki.org/ptwiktionary/). Todas as definições ficam em português: português, e inglês, espanhol, francês, italiano, alemão, latim e japonês → português.

```sh
curl -LO https://kaikki.org/ptwiktionary/raw-wiktextract-data.jsonl.gz
python3 dicionarios/montar_wikcionario.py raw-wiktextract-data.jsonl.gz saida/
tar -C saida -czf - . | ssh root@KINDLE 'tar -xzf - -C /mnt/us/koreader/data/dict'
```

O conteúdo vem do Wikcionário, sob licença CC BY-SA.

## Ajustes de leitura

`koreader/ajustes.lua` aplica, com o KOReader **fechado**:

- fonte padrão Literata;
- entrelinha e margens um pouco maiores e kerning melhor;
- hifenização em português;
- capa do livro como tela de descanso;
- desligamento automático após 30 minutos;
- construtor de vocabulário ligado;
- capítulo na barra de status;
- dicionários em português primeiro;
- toque no canto inferior direito para o modo noturno.

```sh
scp -O koreader/ajustes.lua root@KINDLE:/mnt/us/koreader/
ssh root@KINDLE 'cd /mnt/us/koreader && cp settings.reader.lua settings.reader.lua.bak && ./luajit ajustes.lua'
```

As fontes (Literata, EB Garamond, Crimson Pro, Atkinson Hyperlegible, todas sob licença OFL) vão em `/mnt/us/fonts`. As fontes variáveis precisam ser convertidas em estáticas antes, por exemplo com o `fontTools`.
