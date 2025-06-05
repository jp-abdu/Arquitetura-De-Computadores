;***************************************************************************
;* PROJETO ASSEMBLY ATMEGA2560 - PROCESSAMENTO DE FRASE E TABELAS          *
;* Objetivo Geral do Programa:                                             *
;* 1. Ler uma frase pré-definida (exemplo: "joao 2024").                   *
;* 2. Comparar cada caractere da frase com uma lista especial de 15        *
;* caracteres também pré-definida.										   *
;* 3. Criar uma nova tabela que resume as informações sobre cada           *
;* caractere único encontrado na frase: qual é o caractere, quantas        *
;* vezes ele apareceu, e se ele pertencia ou não à lista especial.         *
;***************************************************************************

;***************************************************************************
;* Definições do Microcontrolador e Diretivas Iniciais                     *
;* Estas linhas preparam o ambiente para o montador entender as instruções.*
;***************************************************************************
.NOLIST                 
.INCLUDE "m2560def.inc" 
.LIST                   

;***************************************************************************
;* Definições de Constantes                                                *
;* A diretiva ".EQU" define nomes simbólicos (apelidos) para valores       *
;* fixos. Isso torna o código mais fácil de ler e modificar, pois usamos   *
;* nomes em vez de números "mágicos".                                      *
;***************************************************************************

.EQU TABELA_ASCII_ADDR    = 0x0200  ; Local na Memória RAM para a tabela de 15 caracteres de referência.
.EQU FRASE_ADDR            = 0x0300  ; Local na Memória RAM para a frase a ser analisada.
.EQU TABELA_SAIDA_ADDR    = 0x0400  ; Local na Memória RAM onde a tabela de resultados será construída.

.EQU TAMANHO_TABELA_ASCII   = 15      ; Número de caracteres na tabela de referência.
.EQU TAMANHO_MAX_FRASE     = 30      ; Espaço máximo (em bytes) reservado na Memória RAM para a frase.
.EQU TAMANHO_FRASE_LITERAL_COM_NULL = 10 ; Tamanho exato da frase de exemplo "joao 2024" mais o caractere nulo final.
.EQU TAMANHO_ENTRADA_SAIDA  = 3       ; Cada entrada na tabela de saída ocupará 3 bytes:
                                      ;   1 byte: O próprio caractere (seu código ASCII).
                                      ;   1 byte: Quantas vezes o caractere apareceu na frase.
                                      ;   1 byte: Uma "flag" (marcador, valendo 0 ou 1) indicando se o caractere pertencia à tabela de referência de 15 caracteres.
.EQU END_OF_STRING         = 0x00    ; Caractere especial (com valor numérico zero, chamado "nulo") que marca o fim de uma string (sequência de caracteres) ou frase.
                                      
;*********************************************************************************
;* - Ponteiros (X, Y, Z): São pares especiais de registradores                   *
;* (X=R27:R26, Y=R29:R28, Z=R31:R30) usados para guardar endereços de            *
;* memória. Eles "apontam" para locais na memória                                *
;* - Ponteiro Z: Escolhido para ler dados da memória de programa (Flash)         *
;* durante a cópia inicial e para ler a frase da Memória RAM.                    *
;* - Ponteiro X: Escolhido para ler e escrever na tabela de saída na             *
;* Memória RAM, e também usado como ponteiro de destino na cópia inicial         *
;* de dados da Flash para a RAM.                                                 *
;* - Ponteiro Y: Escolhido para varrer (ler sequencialmente) a tabela de         *
;* referência na Memória RAM.                                                    *
;* - Registrador R0: Usado na sub-rotina ATUALIZA_TABELA_SAIDA para guardar      *
;* As instruções PUSH (empilhar) e POP (desempilhar) são usadas para salvar      *
;* valores de registradores temporariamente na "pilha" (uma área da RAM)         *
;* quando uma sub-rotina precisa usar esses registradores,garantindo que o valor *
;* garantindo que o valor original do registrador seja restaurado quando         *
;* a sub-rotina terminar.                                                        *
;*********************************************************************************

.DEF temp_reg  = R16 ; Registrador para uso geral e temporário.
.DEF temp_reg2 = R23 ; Outro registrador para uso geral e temporário.
.DEF char_lido = R17 ; Armazena o caractere da frase que está sendo analisado no momento.
.DEF char_tabela_ascii = R18 ; Armazena o caractere da tabela de referência que está sendo comparado.
.DEF flag_pertence_tabela = R20 ; Armazena 0 ou 1: 1 se 'char_lido' foi encontrado na tabela de referência, 0 caso contrário.
.DEF contador_loop_interno = R21 ; Usado como contador para controlar repetições em loops (por exemplo, ao varrer a tabela de referência).
.DEF contador_copia_flash = R24 ; Usado como contador nas rotinas que copiam dados da memória Flash para a Memória RAM. Também usado como contador de busca na tabela de saída.

; --- Registrador Global ---
.DEF ptr_saida_offset = R22 ; Conta quantas entradas (caracteres únicos) já foram adicionadas à tabela de saída. Ajuda a saber onde escrever o próximo novo caractere na tabela de saída.

; --- Macros para salvar/restaurar 5 registradores na "pilha" ---

.MACRO mSaveRegs5 ; Macro para "empilhar" (salvar) 5 registradores.
                  ; Os nomes p0, p1, etc., na definição da macro são substituídos pelos nomes dos registradores passados quando a macro é chamada.
                  ; Dentro da macro, @0 refere-se ao primeiro argumento, @1 ao segundo, etc.
    PUSH @0  ; Instrução PUSH: Coloca o valor do registrador especificado no topo da pilha.
    PUSH @1
    PUSH @2
    PUSH @3
    PUSH @4
.ENDM

.MACRO mRestoreRegs5 ; Macro para "desempilhar" (restaurar) 5 registradores.
    POP @4           ; Instrução POP: Retira o valor do topo da pilha e coloca no registrador especificado.
                     ; A ordem é inversa à do PUSH, seguindo o princípio LIFO (Last In, First Out - o último a entrar é o primeiro a sair).
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
;* Segmento de Dados (.DSEG) - Alocação de espaço na SRAM (RAM Interna)    *
;***************************************************************************

.DSEG ; Indica que as definições a seguir são para a memória de dados (SRAM).
.ORG TABELA_ASCII_ADDR ; Define que a reserva de memória a seguir começa no endereço 0x0200.
TABELA_ASCII_15_CARACTERES:
    .BYTE TAMANHO_TABELA_ASCII ; Reserva 15 bytes na SRAM para a tabela de referência ASCII.

.ORG FRASE_ADDR ; Define que a reserva de memória a seguir começa no endereço 0x0300.
FRASE_USUARIO:
    .BYTE TAMANHO_MAX_FRASE    ; Reserva 30 bytes na SRAM para a frase que será analisada.

.ORG TABELA_SAIDA_ADDR ; Define que a reserva de memória a seguir começa no endereço 0x0400.
TABELA_SAIDA_DADOS:
    ; Reserva espaço para a tabela de saída (resultados).
    ; (30 entradas possíveis * 3 bytes por entrada = 90 bytes).
    .BYTE (TAMANHO_MAX_FRASE * TAMANHO_ENTRADA_SAIDA)

;***************************************************************************
;* Segmento de Código (.CSEG)                                              *
;***************************************************************************
.CSEG ; Indica que as definições a seguir são para a memória de código (Flash).
.ORG 0x0000      ; Define o endereço inicial do programa, conhecido como vetor de Reset.
                 ; Quando o microcontrolador é ligado ou resetado, ele começa a executar a instrução que estiver neste endereço.

    RJMP RESET_HANDLER ; Instrução RJMP (Relative Jump - Salto Relativo): Pula para a rotina de inicialização chamada RESET_HANDLER.

.ORG 0x0100 ; Define um endereço na memória Flash para armazenar dados constantes do programa. 0x0100 é um endereço de PALAVRA (16 bits) equivalente ao endereço de BYTE 0x0200 na Flash

TABELA_ASCII_FLASH: ; Estes são os 15 caracteres de referência, armazenados permanentemente na Flash.
    .DB 'A', 'b', 'C', 'd', 'E', 'f', 'G', 'h', 'I', 'j', '1', '2', '3', '4', '5'

FRASE_USUARIO_FLASH: ; Esta é a frase de teste, armazenada permanentemente na Flash.
    .DB "joao 2024", END_OF_STRING ; A frase inclui o caractere nulo no final para marcar seu término.

RESET_HANDLER: ; Etiqueta que marca o início da rotina de inicialização do sistema.
			   ; 1. Inicialização da Stack Pointer (Ponteiro da Pilha)

    LDI temp_reg, HIGH(RAMEND) ; Instrução LDI (Load Immediate - Carregar Imediato): Carrega a parte alta do endereço final da RAM no registrador temporário.
    OUT SPH, temp_reg          ; Instrução OUT: Envia o valor do registrador temporário para o registrador especial SPH (Stack Pointer High - Parte Alta do Ponteiro da Pilha).
    LDI temp_reg, LOW(RAMEND)  ; Carrega a parte baixa do endereço final da RAM.
    OUT SPL, temp_reg          ; Configura o registrador SPL (Stack Pointer Low - Parte Baixa do Ponteiro da Pilha).

    ; Copiando TABELA_ASCII_FLASH para TABELA_ASCII_15_CARACTERES (destino na SRAM)
    LDI ZL, LOW(TABELA_ASCII_FLASH*2)   ; Configura o Ponteiro Z (R31:R30) para apontar para o início dos dados da tabela ASCII na memória Flash.
    LDI ZH, HIGH(TABELA_ASCII_FLASH*2)  ; O '*2' é necessário porque labels na Flash referem-se a endereços de palavras (16 bits), e o Ponteiro Z espera um endereço de byte.

    LDI XL, LOW(TABELA_ASCII_ADDR)      ; Configura o Ponteiro X (R27:R26) para apontar para o endereço de destino na SRAM (0x0200).
    LDI XH, HIGH(TABELA_ASCII_ADDR)     

    LDI contador_copia_flash, TAMANHO_TABELA_ASCII ; Define quantos bytes copiar (15).

COPIA_ASCII_LOOP: ; Início do loop (repetição) de cópia da tabela ASCII.
    CPI contador_copia_flash, 0          ; Instrução CPI (Compare with Immediate - Comparar com Imediato): Compara o contador com zero.
    BREQ FIM_COPIA_ASCII                 ; Instrução BREQ (Branch if Equal - Desviar se Igual): Se o contador for zero, a cópia terminou, então pula para FIM_COPIA_ASCII.
    LPM temp_reg2, Z+                    ; Instrução LPM (Load from Program Memory - Carregar da Memória de Programa): Lê um byte da Flash apontado por Z, coloca em temp_reg2 (R23),
                                         ; e depois incrementa Z para o próximo byte.

    ST X+, temp_reg2                     ; Instrução ST (Store - Armazenar): Armazena o byte lido (de temp_reg2) na SRAM no local apontado por X, e depois incrementa X.
    DEC contador_copia_flash             ; Instrução DEC (Decrement - Decrementar): Diminui o contador de bytes em 1.
    RJMP COPIA_ASCII_LOOP                ; Instrução RJMP (Relative Jump - Salto Relativo): Volta para o início do loop.
FIM_COPIA_ASCII:    ; Etiqueta para o fim da cópia da tabela ASCII.

    ; Copiando FRASE_USUARIO_FLASH para FRASE_USUARIO (destino na SRAM)
    LDI ZL, LOW(FRASE_USUARIO_FLASH*2)   ; Ponteiro Z aponta para a frase na Flash.
    LDI ZH, HIGH(FRASE_USUARIO_FLASH*2)
    LDI XL, LOW(FRASE_ADDR)              ; Ponteiro X aponta para o destino da frase na SRAM (0x0300).
    LDI XH, HIGH(FRASE_ADDR)
    LDI contador_copia_flash, TAMANHO_FRASE_LITERAL_COM_NULL ; Define quantos bytes copiar (10).
COPIA_FRASE_LOOP: ; Início do loop de cópia da frase.
    CPI contador_copia_flash, 0
    BREQ FIM_COPIA_FRASE
    LPM temp_reg2, Z+
    ST X+, temp_reg2
    DEC contador_copia_flash
    RJMP COPIA_FRASE_LOOP
FIM_COPIA_FRASE:    ; Etiqueta para o fim da cópia da frase.
    ; --- Fim da Rotina de Cópia ---

    ; 2. Inicializar variáveis globais do programa
    CLR ptr_saida_offset ; Instrução CLR (Clear - Limpar): Zera o registrador ptr_saida_offset (R22). Este registrador conta as entradas na tabela de saída, então começa em zero.

    ; 3. Chamar a rotina principal de processamento da frase
    RCALL PROCESSA_FRASE ; Instrução RCALL (Relative Call - Chamada Relativa): Chama a sub-rotina PROCESSA_FRASE. O programa desvia para essa sub-rotina e, quando ela
                         ; terminar (com uma instrução RET), voltará para a instrução seguinte a esta.

END_PROGRAM: ; O processamento principal da frase terminou.
    RJMP END_PROGRAM ; Loop infinito. Faz o processador ficar "preso" aqui.
                     ; Isso indica o fim da execução principal e permite que o estado da memória e dos registradores seja inspecionado com calma no simulador.

;***************************************************************************
;* Sub-rotina: PROCESSA_FRASE                                              *
;* Objetivo: Ela lê a frase da SRAM, caractere por caractere.              *
;* Para cada caractere lido, ela chama outras sub-rotinas                  *
;* para verificar se ele pertence à tabela de referência e para registrá-lo*
;* (ou atualizar sua contagem) na tabela de saída.                         *
;***************************************************************************

PROCESSA_FRASE:
    ; Configura o ponteiro Z para apontar para o início da FRASE_USUARIO na SRAM (endereço 0x0300).
    LDI ZL, LOW(FRASE_ADDR)   ; Carrega a parte baixa do endereço da frase em ZL (R30).
    LDI ZH, HIGH(FRASE_ADDR)  ; Carrega a parte alta do endereço da frase em ZH (R31).

PROXIMO_CARACTERE_FRASE: ; Etiqueta para o loop principal desta sub-rotina: processa um caractere por vez.
    ; Carrega o caractere da SRAM (do local apontado por Z) para o registrador char_lido (R17).
    ; O 'Z+' significa que o ponteiro Z é incrementado automaticamente após a leitura, para que na próxima vez ele aponte para o próximo caractere da frase.

    LD char_lido, Z+ ; Instrução LD (Load - Carregar): Carrega dado da SRAM.

    CPI char_lido, END_OF_STRING ; Compara o valor em char_lido com o valor de END_OF_STRING (0).
    BREQ FIM_PROCESSA_FRASE      ; Se forem iguais (a frase terminou), pula para a etiqueta FIM_PROCESSA_FRASE.

    ; --- Se não for o fim da string, o caractere lido precisa ser processado ---
    ; 1. Verifica se o char_lido (R17) está na lista de 15 caracteres de referência.
    ;    O resultado desta verificação (0 ou 1) será colocado no registrador flag_pertence_tabela (R20).
    RCALL VERIFICA_NA_TABELA_INICIAL

    ; 2. Adiciona o char_lido (R17) à tabela de saída ou atualiza sua contagem se já estiver lá.
    ;    Esta sub-rotina usa o char_lido (R17) e a flag (R20) como entrada.
    ;    Ela também pode atualizar o ptr_saida_offset (R22) se um novo caractere único for adicionado.
    RCALL ATUALIZA_TABELA_SAIDA

    RJMP PROXIMO_CARACTERE_FRASE ; Volta para a etiqueta PROXIMO_CARACTERE_FRASE para ler o próximo caractere.

FIM_PROCESSA_FRASE:
    RET ; Instrução RET (Return - Retornar): Retorna da sub-rotina para o local de onde ela foi chamada (que foi dentro do RESET_HANDLER).

;***************************************************************************
;* Sub-rotina: VERIFICA_NA_TABELA_INICIAL                                  *
;* Objetivo: Esta sub-rotina recebe um caractere no registrador            *
;* char_lido (R17). Ela então verifica se este caractere existe na         *
;* TABELA_ASCII_15_CARACTERES (que está na SRAM).                          *
;* Ao final, ela define o registrador flag_pertence_tabela (R20) como 1 se *
;* o caractere foi encontrado, ou 0 caso contrário.                        *
;***************************************************************************

VERIFICA_NA_TABELA_INICIAL:
    ; Salva os valores atuais de alguns registradores na pilha usando a macro.
    ; Isso é feito porque esta sub-rotina vai usar esses registradores para seus próprios cálculos, e não queremos alterar os valores que eles continham antes de esta sub-rotina ser chamada.
    mSaveRegs5 temp_reg, char_tabela_ascii, contador_loop_interno, YL, YH 

    CLR flag_pertence_tabela ; Começa assumindo que o caractere NÃO pertence à tabela de referência (coloca 0 no registrador R20).

    ; Configura o ponteiro Y para apontar para o início da TABELA_ASCII_15_CARACTERES na SRAM (endereço 0x0200).
    LDI temp_reg, LOW(TABELA_ASCII_ADDR) ; Carrega a parte baixa do endereço em temp_reg (R16).
    MOV YL, temp_reg                     ; Instrução MOV (Move - Mover/Copiar): Copia o valor de temp_reg para YL (R28).
    LDI temp_reg, HIGH(TABELA_ASCII_ADDR); Carrega a parte alta do endereço.
    MOV YH, temp_reg                     ; Copia para YH (R29). Agora Y (YH:YL) aponta para 0x0200.

    ; Prepara um contador (contador_loop_interno, R21) para varrer todos os 15 caracteres da tabela de referência.
    LDI contador_loop_interno, TAMANHO_TABELA_ASCII

VT_LOOP_CMP: ; Etiqueta para o loop que compara char_lido com cada item da tabela de referência.
    ; Carrega um caractere da tabela de referência (do local apontado por Y) para o registrador char_tabela_ascii (R18).
    ; O 'Y+' significa que o ponteiro Y é incrementado automaticamente após a leitura, para que na próxima vez ele aponte para o próximo caractere da tabela de referência.
    LD char_tabela_ascii, Y+

    ; Compara o caractere da frase (char_lido, R17) com o caractere atualmente lido da tabela de referência (char_tabela_ascii, R18).
    CP char_lido, char_tabela_ascii ; Instrução CP (Compare - Comparar).
    BRNE VT_CONTINUA_LOOP           ; Instrução BRNE (Branch if Not Equal - Desviar se Não For Igual): Se os caracteres NÃO forem iguais, continua o loop (pula para VT_CONTINUA_LOOP).

    ; Se o programa chegou aqui, é porque os caracteres SÃO IGUAIS (o caractere da frase foi encontrado na tabela de referência).
    LDI flag_pertence_tabela, 1     ; Define a flag (R20) para 1 (indicando que "pertence").
    RJMP VT_FIM_VERIFICACAO         ; Já encontrou o caractere, então pode pular para o fim da sub-rotina.

VT_CONTINUA_LOOP: ; Etiqueta para onde o programa pula se os caracteres não eram iguais.
    DEC contador_loop_interno       ; Diminui em 1 o contador de caracteres restantes na tabela de referência.
    BRNE VT_LOOP_CMP                ; Se o contador ainda não for zero (ou seja, ainda há caracteres para testar), volta para o início do loop (VT_LOOP_CMP).

VT_FIM_VERIFICACAO: ; Etiqueta para o fim da busca na tabela de referência (seja por ter encontrado ou por ter testado todos).
    ; Restaura os valores originais dos registradores que foram salvos no início desta sub-rotina.
    ; Eles são retirados da pilha na ordem inversa em que foram colocados, usando a macro.
    mRestoreRegs5 temp_reg, char_tabela_ascii, contador_loop_interno, YL, YH
    RET ; Retorna da sub-rotina. O valor da flag (0 ou 1) está em R20.

;***************************************************************************
;* Sub-rotina: ATUALIZA_TABELA_SAIDA                                       *
;* Objetivo: Esta sub-rotina recebe um caractere (em char_lido, R17) e uma *
;* flag (em flag_pertence_tabela, R20).                                    *
;* Sua função é adicionar este caractere à tabela de saída                 *
;* (TABELA_SAIDA_DADOS, na SRAM em 0x0400) ou, se o caractere já estiver   *
;* listado lá, apenas incrementar sua contagem de ocorrências.             *
;* A flag recebida (0 ou 1) também é armazenada junto com o caractere e a  *
;* contagem.                                                               *
;***************************************************************************
ATUALIZA_TABELA_SAIDA:
    ; Salva na pilha os registradores que serão usados temporariamente por esta sub-rotina.
    mSaveRegs7 temp_reg, temp_reg2, R24, R25, R0, XL, XH

    ; --- Fase 1: Procurar se char_lido (R17) já existe na TABELA_SAIDA_DADOS ---
    ; Configura o ponteiro X para apontar para o início da TABELA_SAIDA_DADOS na SRAM (0x0400).
    LDI XL, LOW(TABELA_SAIDA_ADDR)
    LDI XH, HIGH(TABELA_SAIDA_ADDR)

    ; O registrador R24 (apelidado de contador_copia_flash, mas aqui usado como contador_busca) recebe o número de entradas (caracteres únicos) que já existem na tabela de saída.
    ; Este número está armazenado em ptr_saida_offset (R22).
    MOV R24, ptr_saida_offset
    TST R24                          ; Instrução TST (Test - Testar): Verifica se R24 é zero.
    BREQ ATS_ADICIONA_NOVA_ENTRADA   ; Se R24 for zero (ou seja, a tabela de saída está vazia), não há o que buscar, então pula direto para adicionar o novo caractere.

ATS_LOOP_BUSCA: ; Etiqueta para o loop que procura char_lido dentro da tabela de saída existente.
    ; Cada entrada na tabela de saída tem 3 bytes: [Caractere][Contagem][Flag]. O ponteiro X está apontando para o byte do Caractere da entrada atual que está sendo verificada.
    LD R25, X                        ; Carrega o caractere armazenado na tabela de saída (apontado por X) para o registrador temporário R25 (apelidado de char_atual_saida).
    CP char_lido, R25                ; Compara o char_lido (R17, da frase) com o caractere da tabela de saída (R25).
    BRNE ATS_PROXIMA_ENTRADA_BUSCA   ; Se NÃO forem iguais, pula para verificar a próxima entrada na tabela de saída.

    ; Se chegou aqui, significa que o caractere FOI ENCONTRADO na tabela de saída!
    ; O ponteiro X ainda aponta para o byte do caractere. Precisamos incrementar a contagem, que é o byte seguinte na memória.
    ADIW XL, 1                       ; Instrução ADIW (Add Immediate to Word - Adicionar Imediato a Palavra): Avança o ponteiro X em 1 byte (X = X+1). Agora X aponta para o byte de contagem.
                                     ; (XL refere-se à parte baixa do par XH:XL, mas ADIW opera no par de 16 bits).
    LD R0, X                         ; Carrega a contagem atual (da memória, apontada por X) para o registrador R0.
    INC R0                           ; Instrução INC (Increment - Incrementar): Aumenta a contagem em R0 em 1.
    ST X, R0                         ; Salva a nova contagem (de R0) de volta na memória, no mesmo local.
    RJMP ATS_FIM_ATUALIZACAO         ; O trabalho para este caractere (que já existia) está concluído. Pula para o fim.

ATS_PROXIMA_ENTRADA_BUSCA: ; Etiqueta para quando o caractere não coincidiu com a entrada atual da tabela de saída.
    ; Precisamos avançar o ponteiro X para o início da PRÓXIMA entrada na tabela de saída.
    ; Como cada entrada tem TAMANHO_ENTRADA_SAIDA (3) bytes, avançamos X em 3 posições.
    ADIW XL, TAMANHO_ENTRADA_SAIDA
    DEC R24                          ; Decrementa o contador de entradas restantes para buscar (R24).
    BRNE ATS_LOOP_BUSCA              ; Se ainda há entradas para verificar (R24 não é zero), continua buscando.

    ; Se o loop terminou (R24 chegou a zero) e o caractere não foi encontrado na tabela de saída, então ele precisa ser adicionado como uma nova entrada.
ATS_ADICIONA_NOVA_ENTRADA:
    ; --- Fase 2: Adicionar uma nova entrada para char_lido na TABELA_SAIDA_DADOS ---
    ; Primeiro, precisamos calcular o endereço exato na memória onde esta nova entrada será escrita.
    ; Endereço = EndereçoInicialDaTabelaDeSaída + (NúmeroDeEntradasAtuais * TamanhoDeCadaEntrada)
    ; O registrador ptr_saida_offset (R22) contém o número de entradas atuais, o TamanhoDeCadaEntrada é 3 bytes.

    MOV temp_reg, ptr_saida_offset   ; Copia o número de entradas atuais (de R22) para temp_reg (R16). Vamos chamar este valor de N.
    CLR temp_reg2                    ; Zera temp_reg2 (R23). Usaremos R23:R0 para o cálculo do deslocamento (offset), e como o offset máximo (30*3=90) cabe em um byte, R23 (parte alta) será 0.

    CPI temp_reg, 0                  ; Compara N (em temp_reg) com 0.
    BREQ ATS_SKIP_MULT_OFFSET        ; Se N for 0 (tabela estava vazia), o offset é 0. Pula o cálculo da multiplicação.

ATS_CALC_OFFSET_NON_ZERO: ; Etiqueta para o caso de N > 0. Calcula Offset = N * 3.
    MOV R0, temp_reg                 ; Copia N para R0 (para preservar N em temp_reg, R16).
    LSL R0                           ; Instrução LSL (Logical Shift Left - Deslocamento Lógico à Esquerda): Multiplica R0 por 2 (R0 = 2*N).
    ADD R0, temp_reg                 ; Instrução ADD (Add - Adicionar): Adiciona N (de temp_reg) a 2*N (em R0). Resultado: R0 = 2*N + N = 3*N. R0 agora contém o offset em bytes.
    RJMP ATS_APLICA_OFFSET           ; Pula para aplicar o offset.

ATS_SKIP_MULT_OFFSET:				 ; Etiqueta para o caso de N ter sido 0.
    CLR R0                           ; Garante que R0 (offset) seja 0.

ATS_APLICA_OFFSET:
    ; Agora, configuramos o ponteiro X para o local exato da nova entrada.
    ; X = EndereçoBaseDaTabelaDeSaida (0x0400) + OffsetCalculado (que está em R0).
    LDI XL, LOW(TABELA_SAIDA_ADDR)   ; Carrega parte baixa de 0x0400 em XL.
    LDI XH, HIGH(TABELA_SAIDA_ADDR)  ; Carrega parte alta de 0x0400 em XH.

    ADD XL, R0         ; Adiciona a parte baixa do offset (R0) a XL.
    ADC XH, temp_reg2  ; Instrução ADC (Add with Carry - Adicionar com Transporte/Vai-Um): Adiciona a parte alta do offset (R23, que é 0) a XH, mais qualquer "vai-um" da soma anterior (ADD XL, R0).

    ; O ponteiro X agora aponta para o local correto na memória para a nova entrada.
    ; Vamos escrever os 3 bytes da nova entrada: 1. O Caractere (que está em char_lido, R17)
    ST X+, char_lido                 ; Salva o valor de R17 na memória (no local apontado por X) e incrementa X para apontar para o próximo byte.

    ; 2. A Contagem (que será inicialmente 1, pois esta é a primeira vez que este caractere é adicionado)
    LDI temp_reg, 1                  ; Coloca o valor 1 em temp_reg (R16).
    ST X+, temp_reg                  ; Salva 1 na memória (em X) e incrementa X.

    ; 3. A Flag (que está em flag_pertence_tabela, R20)
    ST X, flag_pertence_tabela       ; Salva o valor de R20 na memória (em X). Não precisa incrementar X aqui, pois é o último byte da entrada.

    ; Como uma nova entrada única foi adicionada, incrementamos o contador global de entradas.
    INC ptr_saida_offset             ; Incrementa R22 (R22 = R22 + 1).

ATS_FIM_ATUALIZACAO: ; Etiqueta para o final da sub-rotina (seja por ter atualizado ou adicionado). Restaura os valores originais dos registradores que foram salvos na pilha no início.

    mRestoreRegs7 temp_reg, temp_reg2, R24, R25, R0, XL, XH
    RET ; Retorna da sub-rotina.