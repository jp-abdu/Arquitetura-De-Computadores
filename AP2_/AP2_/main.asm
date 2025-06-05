;***************************************************************************
;* PROJETO ASSEMBLY ATMEGA2560 - PROCESSAMENTO DE FRASE E TABELAS          *
;* Objetivo Geral do Programa:                                             *
;* 1. Ler uma frase pr�-definida (exemplo: "joao 2024").                   *
;* 2. Comparar cada caractere da frase com uma lista especial de 15        *
;* caracteres tamb�m pr�-definida.										   *
;* 3. Criar uma nova tabela que resume as informa��es sobre cada           *
;* caractere �nico encontrado na frase: qual � o caractere, quantas        *
;* vezes ele apareceu, e se ele pertencia ou n�o � lista especial.         *
;***************************************************************************

;***************************************************************************
;* Defini��es do Microcontrolador e Diretivas Iniciais                     *
;* Estas linhas preparam o ambiente para o montador entender as instru��es.*
;***************************************************************************
.NOLIST                 
.INCLUDE "m2560def.inc" 
.LIST                   

;***************************************************************************
;* Defini��es de Constantes                                                *
;* A diretiva ".EQU" define nomes simb�licos (apelidos) para valores       *
;* fixos. Isso torna o c�digo mais f�cil de ler e modificar, pois usamos   *
;* nomes em vez de n�meros "m�gicos".                                      *
;***************************************************************************

.EQU TABELA_ASCII_ADDR    = 0x0200  ; Local na Mem�ria RAM para a tabela de 15 caracteres de refer�ncia.
.EQU FRASE_ADDR            = 0x0300  ; Local na Mem�ria RAM para a frase a ser analisada.
.EQU TABELA_SAIDA_ADDR    = 0x0400  ; Local na Mem�ria RAM onde a tabela de resultados ser� constru�da.

.EQU TAMANHO_TABELA_ASCII   = 15      ; N�mero de caracteres na tabela de refer�ncia.
.EQU TAMANHO_MAX_FRASE     = 30      ; Espa�o m�ximo (em bytes) reservado na Mem�ria RAM para a frase.
.EQU TAMANHO_FRASE_LITERAL_COM_NULL = 10 ; Tamanho exato da frase de exemplo "joao 2024" mais o caractere nulo final.
.EQU TAMANHO_ENTRADA_SAIDA  = 3       ; Cada entrada na tabela de sa�da ocupar� 3 bytes:
                                      ;   1 byte: O pr�prio caractere (seu c�digo ASCII).
                                      ;   1 byte: Quantas vezes o caractere apareceu na frase.
                                      ;   1 byte: Uma "flag" (marcador, valendo 0 ou 1) indicando se o caractere pertencia � tabela de refer�ncia de 15 caracteres.
.EQU END_OF_STRING         = 0x00    ; Caractere especial (com valor num�rico zero, chamado "nulo") que marca o fim de uma string (sequ�ncia de caracteres) ou frase.
                                      
;*********************************************************************************
;* - Ponteiros (X, Y, Z): S�o pares especiais de registradores                   *
;* (X=R27:R26, Y=R29:R28, Z=R31:R30) usados para guardar endere�os de            *
;* mem�ria. Eles "apontam" para locais na mem�ria                                *
;* - Ponteiro Z: Escolhido para ler dados da mem�ria de programa (Flash)         *
;* durante a c�pia inicial e para ler a frase da Mem�ria RAM.                    *
;* - Ponteiro X: Escolhido para ler e escrever na tabela de sa�da na             *
;* Mem�ria RAM, e tamb�m usado como ponteiro de destino na c�pia inicial         *
;* de dados da Flash para a RAM.                                                 *
;* - Ponteiro Y: Escolhido para varrer (ler sequencialmente) a tabela de         *
;* refer�ncia na Mem�ria RAM.                                                    *
;* - Registrador R0: Usado na sub-rotina ATUALIZA_TABELA_SAIDA para guardar      *
;* As instru��es PUSH (empilhar) e POP (desempilhar) s�o usadas para salvar      *
;* valores de registradores temporariamente na "pilha" (uma �rea da RAM)         *
;* quando uma sub-rotina precisa usar esses registradores,garantindo que o valor *
;* garantindo que o valor original do registrador seja restaurado quando         *
;* a sub-rotina terminar.                                                        *
;*********************************************************************************

.DEF temp_reg  = R16 ; Registrador para uso geral e tempor�rio.
.DEF temp_reg2 = R23 ; Outro registrador para uso geral e tempor�rio.
.DEF char_lido = R17 ; Armazena o caractere da frase que est� sendo analisado no momento.
.DEF char_tabela_ascii = R18 ; Armazena o caractere da tabela de refer�ncia que est� sendo comparado.
.DEF flag_pertence_tabela = R20 ; Armazena 0 ou 1: 1 se 'char_lido' foi encontrado na tabela de refer�ncia, 0 caso contr�rio.
.DEF contador_loop_interno = R21 ; Usado como contador para controlar repeti��es em loops (por exemplo, ao varrer a tabela de refer�ncia).
.DEF contador_copia_flash = R24 ; Usado como contador nas rotinas que copiam dados da mem�ria Flash para a Mem�ria RAM. Tamb�m usado como contador de busca na tabela de sa�da.

; --- Registrador Global ---
.DEF ptr_saida_offset = R22 ; Conta quantas entradas (caracteres �nicos) j� foram adicionadas � tabela de sa�da. Ajuda a saber onde escrever o pr�ximo novo caractere na tabela de sa�da.

; --- Macros para salvar/restaurar 5 registradores na "pilha" ---

.MACRO mSaveRegs5 ; Macro para "empilhar" (salvar) 5 registradores.
                  ; Os nomes p0, p1, etc., na defini��o da macro s�o substitu�dos pelos nomes dos registradores passados quando a macro � chamada.
                  ; Dentro da macro, @0 refere-se ao primeiro argumento, @1 ao segundo, etc.
    PUSH @0  ; Instru��o PUSH: Coloca o valor do registrador especificado no topo da pilha.
    PUSH @1
    PUSH @2
    PUSH @3
    PUSH @4
.ENDM

.MACRO mRestoreRegs5 ; Macro para "desempilhar" (restaurar) 5 registradores.
    POP @4           ; Instru��o POP: Retira o valor do topo da pilha e coloca no registrador especificado.
                     ; A ordem � inversa � do PUSH, seguindo o princ�pio LIFO (Last In, First Out - o �ltimo a entrar � o primeiro a sair).
    POP @3
    POP @2
    POP @1
    POP @0
.ENDM

; --- Macros para salvar/restaurar 7 registradores na "pilha" ---
.MACRO mSaveRegs7
    PUSH @0
    PUSH @1
    PUSH @2
    PUSH @3
    PUSH @4
    PUSH @5
    PUSH @6
.ENDM

.MACRO mRestoreRegs7
    POP @6
    POP @5
    POP @4
    POP @3
    POP @2
    POP @1
    POP @0
.ENDM

;***************************************************************************
;* Segmento de Dados (.DSEG) - Aloca��o de espa�o na SRAM (RAM Interna)    *
;***************************************************************************

.DSEG ; Indica que as defini��es a seguir s�o para a mem�ria de dados (SRAM).
.ORG TABELA_ASCII_ADDR ; Define que a reserva de mem�ria a seguir come�a no endere�o 0x0200.
TABELA_ASCII_15_CARACTERES:
    .BYTE TAMANHO_TABELA_ASCII ; Reserva 15 bytes na SRAM para a tabela de refer�ncia ASCII.

.ORG FRASE_ADDR ; Define que a reserva de mem�ria a seguir come�a no endere�o 0x0300.
FRASE_USUARIO:
    .BYTE TAMANHO_MAX_FRASE    ; Reserva 30 bytes na SRAM para a frase que ser� analisada.

.ORG TABELA_SAIDA_ADDR ; Define que a reserva de mem�ria a seguir come�a no endere�o 0x0400.
TABELA_SAIDA_DADOS:
    ; Reserva espa�o para a tabela de sa�da (resultados).
    ; (30 entradas poss�veis * 3 bytes por entrada = 90 bytes).
    .BYTE (TAMANHO_MAX_FRASE * TAMANHO_ENTRADA_SAIDA)

;***************************************************************************
;* Segmento de C�digo (.CSEG)                                              *
;***************************************************************************
.CSEG ; Indica que as defini��es a seguir s�o para a mem�ria de c�digo (Flash).
.ORG 0x0000      ; Define o endere�o inicial do programa, conhecido como vetor de Reset.
                 ; Quando o microcontrolador � ligado ou resetado, ele come�a a executar a instru��o que estiver neste endere�o.

    RJMP RESET_HANDLER ; Instru��o RJMP (Relative Jump - Salto Relativo): Pula para a rotina de inicializa��o chamada RESET_HANDLER.

.ORG 0x0100 ; Define um endere�o na mem�ria Flash para armazenar dados constantes do programa. 0x0100 � um endere�o de PALAVRA (16 bits) equivalente ao endere�o de BYTE 0x0200 na Flash

TABELA_ASCII_FLASH: ; Estes s�o os 15 caracteres de refer�ncia, armazenados permanentemente na Flash.
    .DB 'A', 'b', 'C', 'd', 'E', 'f', 'G', 'h', 'I', 'j', '1', '2', '3', '4', '5'

FRASE_USUARIO_FLASH: ; Esta � a frase de teste, armazenada permanentemente na Flash.
    .DB "joao 2024", END_OF_STRING ; A frase inclui o caractere nulo no final para marcar seu t�rmino.

RESET_HANDLER: ; Etiqueta que marca o in�cio da rotina de inicializa��o do sistema.
			   ; 1. Inicializa��o da Stack Pointer (Ponteiro da Pilha)

    LDI temp_reg, HIGH(RAMEND) ; Instru��o LDI (Load Immediate - Carregar Imediato): Carrega a parte alta do endere�o final da RAM no registrador tempor�rio.
    OUT SPH, temp_reg          ; Instru��o OUT: Envia o valor do registrador tempor�rio para o registrador especial SPH (Stack Pointer High - Parte Alta do Ponteiro da Pilha).
    LDI temp_reg, LOW(RAMEND)  ; Carrega a parte baixa do endere�o final da RAM.
    OUT SPL, temp_reg          ; Configura o registrador SPL (Stack Pointer Low - Parte Baixa do Ponteiro da Pilha).

    ; Copiando TABELA_ASCII_FLASH para TABELA_ASCII_15_CARACTERES (destino na SRAM)
    LDI ZL, LOW(TABELA_ASCII_FLASH*2)   ; Configura o Ponteiro Z (R31:R30) para apontar para o in�cio dos dados da tabela ASCII na mem�ria Flash.
    LDI ZH, HIGH(TABELA_ASCII_FLASH*2)  ; O '*2' � necess�rio porque labels na Flash referem-se a endere�os de palavras (16 bits), e o Ponteiro Z espera um endere�o de byte.

    LDI XL, LOW(TABELA_ASCII_ADDR)      ; Configura o Ponteiro X (R27:R26) para apontar para o endere�o de destino na SRAM (0x0200).
    LDI XH, HIGH(TABELA_ASCII_ADDR)     

    LDI contador_copia_flash, TAMANHO_TABELA_ASCII ; Define quantos bytes copiar (15).

COPIA_ASCII_LOOP: ; In�cio do loop (repeti��o) de c�pia da tabela ASCII.
    CPI contador_copia_flash, 0          ; Instru��o CPI (Compare with Immediate - Comparar com Imediato): Compara o contador com zero.
    BREQ FIM_COPIA_ASCII                 ; Instru��o BREQ (Branch if Equal - Desviar se Igual): Se o contador for zero, a c�pia terminou, ent�o pula para FIM_COPIA_ASCII.
    LPM temp_reg2, Z+                    ; Instru��o LPM (Load from Program Memory - Carregar da Mem�ria de Programa): L� um byte da Flash apontado por Z, coloca em temp_reg2 (R23),
                                         ; e depois incrementa Z para o pr�ximo byte.

    ST X+, temp_reg2                     ; Instru��o ST (Store - Armazenar): Armazena o byte lido (de temp_reg2) na SRAM no local apontado por X, e depois incrementa X.
    DEC contador_copia_flash             ; Instru��o DEC (Decrement - Decrementar): Diminui o contador de bytes em 1.
    RJMP COPIA_ASCII_LOOP                ; Instru��o RJMP (Relative Jump - Salto Relativo): Volta para o in�cio do loop.
FIM_COPIA_ASCII:    ; Etiqueta para o fim da c�pia da tabela ASCII.

    ; Copiando FRASE_USUARIO_FLASH para FRASE_USUARIO (destino na SRAM)
    LDI ZL, LOW(FRASE_USUARIO_FLASH*2)   ; Ponteiro Z aponta para a frase na Flash.
    LDI ZH, HIGH(FRASE_USUARIO_FLASH*2)
    LDI XL, LOW(FRASE_ADDR)              ; Ponteiro X aponta para o destino da frase na SRAM (0x0300).
    LDI XH, HIGH(FRASE_ADDR)
    LDI contador_copia_flash, TAMANHO_FRASE_LITERAL_COM_NULL ; Define quantos bytes copiar (10).
COPIA_FRASE_LOOP: ; In�cio do loop de c�pia da frase.
    CPI contador_copia_flash, 0
    BREQ FIM_COPIA_FRASE
    LPM temp_reg2, Z+
    ST X+, temp_reg2
    DEC contador_copia_flash
    RJMP COPIA_FRASE_LOOP
FIM_COPIA_FRASE:    ; Etiqueta para o fim da c�pia da frase.
    ; --- Fim da Rotina de C�pia ---

    ; 2. Inicializar vari�veis globais do programa
    CLR ptr_saida_offset ; Instru��o CLR (Clear - Limpar): Zera o registrador ptr_saida_offset (R22). Este registrador conta as entradas na tabela de sa�da, ent�o come�a em zero.

    ; 3. Chamar a rotina principal de processamento da frase
    RCALL PROCESSA_FRASE ; Instru��o RCALL (Relative Call - Chamada Relativa): Chama a sub-rotina PROCESSA_FRASE. O programa desvia para essa sub-rotina e, quando ela
                         ; terminar (com uma instru��o RET), voltar� para a instru��o seguinte a esta.

END_PROGRAM: ; O processamento principal da frase terminou.
    RJMP END_PROGRAM ; Loop infinito. Faz o processador ficar "preso" aqui.
                     ; Isso indica o fim da execu��o principal e permite que o estado da mem�ria e dos registradores seja inspecionado com calma no simulador.

;***************************************************************************
;* Sub-rotina: PROCESSA_FRASE                                              *
;* Objetivo: Ela l� a frase da SRAM, caractere por caractere.              *
;* Para cada caractere lido, ela chama outras sub-rotinas                  *
;* para verificar se ele pertence � tabela de refer�ncia e para registr�-lo*
;* (ou atualizar sua contagem) na tabela de sa�da.                         *
;***************************************************************************

PROCESSA_FRASE:
    ; Configura o ponteiro Z para apontar para o in�cio da FRASE_USUARIO na SRAM (endere�o 0x0300).
    LDI ZL, LOW(FRASE_ADDR)   ; Carrega a parte baixa do endere�o da frase em ZL (R30).
    LDI ZH, HIGH(FRASE_ADDR)  ; Carrega a parte alta do endere�o da frase em ZH (R31).

PROXIMO_CARACTERE_FRASE: ; Etiqueta para o loop principal desta sub-rotina: processa um caractere por vez.
    ; Carrega o caractere da SRAM (do local apontado por Z) para o registrador char_lido (R17).
    ; O 'Z+' significa que o ponteiro Z � incrementado automaticamente ap�s a leitura, para que na pr�xima vez ele aponte para o pr�ximo caractere da frase.

    LD char_lido, Z+ ; Instru��o LD (Load - Carregar): Carrega dado da SRAM.

    CPI char_lido, END_OF_STRING ; Compara o valor em char_lido com o valor de END_OF_STRING (0).
    BREQ FIM_PROCESSA_FRASE      ; Se forem iguais (a frase terminou), pula para a etiqueta FIM_PROCESSA_FRASE.

    ; --- Se n�o for o fim da string, o caractere lido precisa ser processado ---
    ; 1. Verifica se o char_lido (R17) est� na lista de 15 caracteres de refer�ncia.
    ;    O resultado desta verifica��o (0 ou 1) ser� colocado no registrador flag_pertence_tabela (R20).
    RCALL VERIFICA_NA_TABELA_INICIAL

    ; 2. Adiciona o char_lido (R17) � tabela de sa�da ou atualiza sua contagem se j� estiver l�.
    ;    Esta sub-rotina usa o char_lido (R17) e a flag (R20) como entrada.
    ;    Ela tamb�m pode atualizar o ptr_saida_offset (R22) se um novo caractere �nico for adicionado.
    RCALL ATUALIZA_TABELA_SAIDA

    RJMP PROXIMO_CARACTERE_FRASE ; Volta para a etiqueta PROXIMO_CARACTERE_FRASE para ler o pr�ximo caractere.

FIM_PROCESSA_FRASE:
    RET ; Instru��o RET (Return - Retornar): Retorna da sub-rotina para o local de onde ela foi chamada (que foi dentro do RESET_HANDLER).

;***************************************************************************
;* Sub-rotina: VERIFICA_NA_TABELA_INICIAL                                  *
;* Objetivo: Esta sub-rotina recebe um caractere no registrador            *
;* char_lido (R17). Ela ent�o verifica se este caractere existe na         *
;* TABELA_ASCII_15_CARACTERES (que est� na SRAM).                          *
;* Ao final, ela define o registrador flag_pertence_tabela (R20) como 1 se *
;* o caractere foi encontrado, ou 0 caso contr�rio.                        *
;***************************************************************************

VERIFICA_NA_TABELA_INICIAL:
    ; Salva os valores atuais de alguns registradores na pilha usando a macro.
    ; Isso � feito porque esta sub-rotina vai usar esses registradores para seus pr�prios c�lculos, e n�o queremos alterar os valores que eles continham antes de esta sub-rotina ser chamada.
    mSaveRegs5 temp_reg, char_tabela_ascii, contador_loop_interno, YL, YH 

    CLR flag_pertence_tabela ; Come�a assumindo que o caractere N�O pertence � tabela de refer�ncia (coloca 0 no registrador R20).

    ; Configura o ponteiro Y para apontar para o in�cio da TABELA_ASCII_15_CARACTERES na SRAM (endere�o 0x0200).
    LDI temp_reg, LOW(TABELA_ASCII_ADDR) ; Carrega a parte baixa do endere�o em temp_reg (R16).
    MOV YL, temp_reg                     ; Instru��o MOV (Move - Mover/Copiar): Copia o valor de temp_reg para YL (R28).
    LDI temp_reg, HIGH(TABELA_ASCII_ADDR); Carrega a parte alta do endere�o.
    MOV YH, temp_reg                     ; Copia para YH (R29). Agora Y (YH:YL) aponta para 0x0200.

    ; Prepara um contador (contador_loop_interno, R21) para varrer todos os 15 caracteres da tabela de refer�ncia.
    LDI contador_loop_interno, TAMANHO_TABELA_ASCII

VT_LOOP_CMP: ; Etiqueta para o loop que compara char_lido com cada item da tabela de refer�ncia.
    ; Carrega um caractere da tabela de refer�ncia (do local apontado por Y) para o registrador char_tabela_ascii (R18).
    ; O 'Y+' significa que o ponteiro Y � incrementado automaticamente ap�s a leitura, para que na pr�xima vez ele aponte para o pr�ximo caractere da tabela de refer�ncia.
    LD char_tabela_ascii, Y+

    ; Compara o caractere da frase (char_lido, R17) com o caractere atualmente lido da tabela de refer�ncia (char_tabela_ascii, R18).
    CP char_lido, char_tabela_ascii ; Instru��o CP (Compare - Comparar).
    BRNE VT_CONTINUA_LOOP           ; Instru��o BRNE (Branch if Not Equal - Desviar se N�o For Igual): Se os caracteres N�O forem iguais, continua o loop (pula para VT_CONTINUA_LOOP).

    ; Se o programa chegou aqui, � porque os caracteres S�O IGUAIS (o caractere da frase foi encontrado na tabela de refer�ncia).
    LDI flag_pertence_tabela, 1     ; Define a flag (R20) para 1 (indicando que "pertence").
    RJMP VT_FIM_VERIFICACAO         ; J� encontrou o caractere, ent�o pode pular para o fim da sub-rotina.

VT_CONTINUA_LOOP: ; Etiqueta para onde o programa pula se os caracteres n�o eram iguais.
    DEC contador_loop_interno       ; Diminui em 1 o contador de caracteres restantes na tabela de refer�ncia.
    BRNE VT_LOOP_CMP                ; Se o contador ainda n�o for zero (ou seja, ainda h� caracteres para testar), volta para o in�cio do loop (VT_LOOP_CMP).

VT_FIM_VERIFICACAO: ; Etiqueta para o fim da busca na tabela de refer�ncia (seja por ter encontrado ou por ter testado todos).
    ; Restaura os valores originais dos registradores que foram salvos no in�cio desta sub-rotina.
    ; Eles s�o retirados da pilha na ordem inversa em que foram colocados, usando a macro.
    mRestoreRegs5 temp_reg, char_tabela_ascii, contador_loop_interno, YL, YH
    RET ; Retorna da sub-rotina. O valor da flag (0 ou 1) est� em R20.

;***************************************************************************
;* Sub-rotina: ATUALIZA_TABELA_SAIDA                                       *
;* Objetivo: Esta sub-rotina recebe um caractere (em char_lido, R17) e uma *
;* flag (em flag_pertence_tabela, R20).                                    *
;* Sua fun��o � adicionar este caractere � tabela de sa�da                 *
;* (TABELA_SAIDA_DADOS, na SRAM em 0x0400) ou, se o caractere j� estiver   *
;* listado l�, apenas incrementar sua contagem de ocorr�ncias.             *
;* A flag recebida (0 ou 1) tamb�m � armazenada junto com o caractere e a  *
;* contagem.                                                               *
;***************************************************************************
ATUALIZA_TABELA_SAIDA:
    ; Salva na pilha os registradores que ser�o usados temporariamente por esta sub-rotina.
    mSaveRegs7 temp_reg, temp_reg2, R24, R25, R0, XL, XH

    ; --- Fase 1: Procurar se char_lido (R17) j� existe na TABELA_SAIDA_DADOS ---
    ; Configura o ponteiro X para apontar para o in�cio da TABELA_SAIDA_DADOS na SRAM (0x0400).
    LDI XL, LOW(TABELA_SAIDA_ADDR)
    LDI XH, HIGH(TABELA_SAIDA_ADDR)

    ; O registrador R24 (apelidado de contador_copia_flash, mas aqui usado como contador_busca) recebe o n�mero de entradas (caracteres �nicos) que j� existem na tabela de sa�da.
    ; Este n�mero est� armazenado em ptr_saida_offset (R22).
    MOV R24, ptr_saida_offset
    TST R24                          ; Instru��o TST (Test - Testar): Verifica se R24 � zero.
    BREQ ATS_ADICIONA_NOVA_ENTRADA   ; Se R24 for zero (ou seja, a tabela de sa�da est� vazia), n�o h� o que buscar, ent�o pula direto para adicionar o novo caractere.

ATS_LOOP_BUSCA: ; Etiqueta para o loop que procura char_lido dentro da tabela de sa�da existente.
    ; Cada entrada na tabela de sa�da tem 3 bytes: [Caractere][Contagem][Flag]. O ponteiro X est� apontando para o byte do Caractere da entrada atual que est� sendo verificada.
    LD R25, X                        ; Carrega o caractere armazenado na tabela de sa�da (apontado por X) para o registrador tempor�rio R25 (apelidado de char_atual_saida).
    CP char_lido, R25                ; Compara o char_lido (R17, da frase) com o caractere da tabela de sa�da (R25).
    BRNE ATS_PROXIMA_ENTRADA_BUSCA   ; Se N�O forem iguais, pula para verificar a pr�xima entrada na tabela de sa�da.

    ; Se chegou aqui, significa que o caractere FOI ENCONTRADO na tabela de sa�da!
    ; O ponteiro X ainda aponta para o byte do caractere. Precisamos incrementar a contagem, que � o byte seguinte na mem�ria.
    ADIW XL, 1                       ; Instru��o ADIW (Add Immediate to Word - Adicionar Imediato a Palavra): Avan�a o ponteiro X em 1 byte (X = X+1). Agora X aponta para o byte de contagem.
                                     ; (XL refere-se � parte baixa do par XH:XL, mas ADIW opera no par de 16 bits).
    LD R0, X                         ; Carrega a contagem atual (da mem�ria, apontada por X) para o registrador R0.
    INC R0                           ; Instru��o INC (Increment - Incrementar): Aumenta a contagem em R0 em 1.
    ST X, R0                         ; Salva a nova contagem (de R0) de volta na mem�ria, no mesmo local.
    RJMP ATS_FIM_ATUALIZACAO         ; O trabalho para este caractere (que j� existia) est� conclu�do. Pula para o fim.

ATS_PROXIMA_ENTRADA_BUSCA: ; Etiqueta para quando o caractere n�o coincidiu com a entrada atual da tabela de sa�da.
    ; Precisamos avan�ar o ponteiro X para o in�cio da PR�XIMA entrada na tabela de sa�da.
    ; Como cada entrada tem TAMANHO_ENTRADA_SAIDA (3) bytes, avan�amos X em 3 posi��es.
    ADIW XL, TAMANHO_ENTRADA_SAIDA
    DEC R24                          ; Decrementa o contador de entradas restantes para buscar (R24).
    BRNE ATS_LOOP_BUSCA              ; Se ainda h� entradas para verificar (R24 n�o � zero), continua buscando.

    ; Se o loop terminou (R24 chegou a zero) e o caractere n�o foi encontrado na tabela de sa�da, ent�o ele precisa ser adicionado como uma nova entrada.
ATS_ADICIONA_NOVA_ENTRADA:
    ; --- Fase 2: Adicionar uma nova entrada para char_lido na TABELA_SAIDA_DADOS ---
    ; Primeiro, precisamos calcular o endere�o exato na mem�ria onde esta nova entrada ser� escrita.
    ; Endere�o = Endere�oInicialDaTabelaDeSa�da + (N�meroDeEntradasAtuais * TamanhoDeCadaEntrada)
    ; O registrador ptr_saida_offset (R22) cont�m o n�mero de entradas atuais, o TamanhoDeCadaEntrada � 3 bytes.

    MOV temp_reg, ptr_saida_offset   ; Copia o n�mero de entradas atuais (de R22) para temp_reg (R16). Vamos chamar este valor de N.
    CLR temp_reg2                    ; Zera temp_reg2 (R23). Usaremos R23:R0 para o c�lculo do deslocamento (offset), e como o offset m�ximo (30*3=90) cabe em um byte, R23 (parte alta) ser� 0.

    CPI temp_reg, 0                  ; Compara N (em temp_reg) com 0.
    BREQ ATS_SKIP_MULT_OFFSET        ; Se N for 0 (tabela estava vazia), o offset � 0. Pula o c�lculo da multiplica��o.

ATS_CALC_OFFSET_NON_ZERO: ; Etiqueta para o caso de N > 0. Calcula Offset = N * 3.
    MOV R0, temp_reg                 ; Copia N para R0 (para preservar N em temp_reg, R16).
    LSL R0                           ; Instru��o LSL (Logical Shift Left - Deslocamento L�gico � Esquerda): Multiplica R0 por 2 (R0 = 2*N).
    ADD R0, temp_reg                 ; Instru��o ADD (Add - Adicionar): Adiciona N (de temp_reg) a 2*N (em R0). Resultado: R0 = 2*N + N = 3*N. R0 agora cont�m o offset em bytes.
    RJMP ATS_APLICA_OFFSET           ; Pula para aplicar o offset.

ATS_SKIP_MULT_OFFSET:				 ; Etiqueta para o caso de N ter sido 0.
    CLR R0                           ; Garante que R0 (offset) seja 0.

ATS_APLICA_OFFSET:
    ; Agora, configuramos o ponteiro X para o local exato da nova entrada.
    ; X = Endere�oBaseDaTabelaDeSaida (0x0400) + OffsetCalculado (que est� em R0).
    LDI XL, LOW(TABELA_SAIDA_ADDR)   ; Carrega parte baixa de 0x0400 em XL.
    LDI XH, HIGH(TABELA_SAIDA_ADDR)  ; Carrega parte alta de 0x0400 em XH.

    ADD XL, R0         ; Adiciona a parte baixa do offset (R0) a XL.
    ADC XH, temp_reg2  ; Instru��o ADC (Add with Carry - Adicionar com Transporte/Vai-Um): Adiciona a parte alta do offset (R23, que � 0) a XH, mais qualquer "vai-um" da soma anterior (ADD XL, R0).

    ; O ponteiro X agora aponta para o local correto na mem�ria para a nova entrada.
    ; Vamos escrever os 3 bytes da nova entrada: 1. O Caractere (que est� em char_lido, R17)
    ST X+, char_lido                 ; Salva o valor de R17 na mem�ria (no local apontado por X) e incrementa X para apontar para o pr�ximo byte.

    ; 2. A Contagem (que ser� inicialmente 1, pois esta � a primeira vez que este caractere � adicionado)
    LDI temp_reg, 1                  ; Coloca o valor 1 em temp_reg (R16).
    ST X+, temp_reg                  ; Salva 1 na mem�ria (em X) e incrementa X.

    ; 3. A Flag (que est� em flag_pertence_tabela, R20)
    ST X, flag_pertence_tabela       ; Salva o valor de R20 na mem�ria (em X). N�o precisa incrementar X aqui, pois � o �ltimo byte da entrada.

    ; Como uma nova entrada �nica foi adicionada, incrementamos o contador global de entradas.
    INC ptr_saida_offset             ; Incrementa R22 (R22 = R22 + 1).

ATS_FIM_ATUALIZACAO: ; Etiqueta para o final da sub-rotina (seja por ter atualizado ou adicionado). Restaura os valores originais dos registradores que foram salvos na pilha no in�cio.

    mRestoreRegs7 temp_reg, temp_reg2, R24, R25, R0, XL, XH
    RET ; Retorna da sub-rotina.