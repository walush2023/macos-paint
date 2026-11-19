import Foundation

// 韓文、法文、德文、西班牙文、義大利文、葡萄牙文翻譯。
// 順序：x(韓, 法, 德, 西, 義, 葡)。key 為繁體中文原字串。
extension L10n {
    static let extra: [String: [Lang: String]] = [
        // 新增功能 / 訊息
        "最近開啟的檔案": x("최근 사용 항목 열기", "Ouvrir l’élément récent", "Benutzte Dokumente", "Abrir recientes", "Apri recenti", "Abrir recentes"),
        "清除選單": x("메뉴 지우기", "Effacer le menu", "Menü löschen", "Borrar menú", "Cancella menu", "Limpar menu"),
        "關閉": x("닫기", "Fermer", "Schließen", "Cerrar", "Chiudi", "Fechar"),
        "透明選取": x("투명 선택", "Sélection transparente", "Transparente Auswahl", "Selección transparente", "Selezione trasparente", "Seleção transparente"),
        "符合視窗": x("윈도우에 맞추기", "Adapter à la fenêtre", "An Fenster anpassen", "Ajustar a la ventana", "Adatta alla finestra", "Ajustar à janela"),
        "反轉色彩": x("색상 반전", "Inverser les couleurs", "Farben umkehren", "Invertir colores", "Inverti colori", "Inverter cores"),
        "清除影像": x("이미지 지우기", "Effacer l’image", "Bild löschen", "Borrar imagen", "Cancella immagine", "Limpar imagem"),
        "無法開啟「%@」：不是支援的影像格式。": x(
            "“%@”을(를) 열 수 없습니다: 지원되지 않는 이미지 형식입니다.",
            "Impossible d’ouvrir « %@ » : format d’image non pris en charge.",
            "„%@“ kann nicht geöffnet werden: kein unterstütztes Bildformat.",
            "No se puede abrir “%@”: formato de imagen no compatible.",
            "Impossibile aprire “%@”: formato immagine non supportato.",
            "Não é possível abrir “%@”: formato de imagem não suportado."),
        "無法儲存「%@」。": x("“%@”을(를) 저장할 수 없습니다.", "Impossible d’enregistrer « %@ ».",
                              "„%@“ kann nicht gesichert werden.", "No se puede guardar “%@”.",
                              "Impossibile salvare “%@”.", "Não é possível salvar “%@”."),

        // App / 視窗 / 標題
        "小畫家": x("그림판", "Paint", "Paint", "Paint", "Paint", "Paint"),
        "小畫家 (macOS 版)": x("macOS용 그림판", "Paint pour macOS", "Paint für macOS", "Paint para macOS", "Paint per macOS", "Paint para macOS"),
        "未命名": x("제목 없음", "Sans titre", "Unbenannt", "Sin título", "Senza titolo", "Sem título"),
        "未命名.png": x("제목 없음.png", "Sans titre.png", "Unbenannt.png", "Sin título.png", "Senza titolo.png", "Sem título.png"),
        "關於小畫家": x("그림판에 관하여", "À propos de Paint", "Über Paint", "Acerca de Paint", "Informazioni su Paint", "Sobre o Paint"),
        "結束小畫家": x("그림판 종료", "Quitter Paint", "Paint beenden", "Salir de Paint", "Esci da Paint", "Encerrar Paint"),
        "Windows 小畫家功能再現\n以原生 AppKit 實作\n\n© 2026": x(
            "Microsoft 그림판 재현\nAppKit 네이티브 구현\n\n© 2026",
            "Une recréation de Microsoft Paint\nDéveloppée nativement avec AppKit\n\n© 2026",
            "Eine Nachbildung von Microsoft Paint\nNativ mit AppKit entwickelt\n\n© 2026",
            "Una recreación de Microsoft Paint\nCreada de forma nativa con AppKit\n\n© 2026",
            "Una ricreazione di Microsoft Paint\nRealizzata in modo nativo con AppKit\n\n© 2026",
            "Uma recriação do Microsoft Paint\nFeita nativamente com AppKit\n\n© 2026"),
        "您要儲存對 %@ 的變更嗎？": x(
            "%@의 변경 사항을 저장하시겠습니까?",
            "Voulez-vous enregistrer les modifications apportées à %@ ?",
            "Möchten Sie die Änderungen an %@ sichern?",
            "¿Quiere guardar los cambios en %@?",
            "Vuoi salvare le modifiche apportate a %@?",
            "Deseja salvar as alterações em %@?"),
        "寬度: %d 像素\n高度: %d 像素\n解析度: 96 DPI": x(
            "너비: %d 픽셀\n높이: %d 픽셀\n해상도: 96 DPI",
            "Largeur : %d pixels\nHauteur : %d pixels\nRésolution : 96 PPP",
            "Breite: %d Pixel\nHöhe: %d Pixel\nAuflösung: 96 DPI",
            "Ancho: %d píxeles\nAlto: %d píxeles\nResolución: 96 PPP",
            "Larghezza: %d pixel\nAltezza: %d pixel\nRisoluzione: 96 DPI",
            "Largura: %d pixels\nAltura: %d pixels\nResolução: 96 DPI"),

        // Tabs / 選單列
        "檔案": x("파일", "Fichier", "Ablage", "Archivo", "File", "Arquivo"),
        "常用": x("홈", "Accueil", "Start", "Inicio", "Home", "Início"),
        "檢視": x("보기", "Présentation", "Darstellung", "Visualización", "Vista", "Visualizar"),
        "編輯": x("편집", "Édition", "Bearbeiten", "Edición", "Modifica", "Editar"),

        // 群組
        "剪貼簿": x("클립보드", "Presse-papiers", "Zwischenablage", "Portapapeles", "Appunti", "Área de transferência"),
        "影像": x("이미지", "Image", "Bild", "Imagen", "Immagine", "Imagem"),
        "工具": x("도구", "Outils", "Werkzeuge", "Herramientas", "Strumenti", "Ferramentas"),
        "容許度": x("허용 오차", "Tolérance", "Toleranz", "Tolerancia", "Tolleranza", "Tolerância"),
        "筆刷": x("브러시", "Pinceaux", "Pinsel", "Pinceles", "Pennelli", "Pincéis"),
        "圖案": x("도형", "Formes", "Formen", "Formas", "Forme", "Formas"),
        "大小": x("크기", "Taille", "Größe", "Tamaño", "Dimensioni", "Tamanho"),
        "色彩": x("색", "Couleurs", "Farben", "Colores", "Colori", "Cores"),
        "顯示或隱藏": x("표시 또는 숨기기", "Afficher ou masquer", "Ein-/ausblenden", "Mostrar u ocultar", "Mostra o nascondi", "Mostrar ou ocultar"),
        "縮放": x("확대/축소", "Zoom", "Zoom", "Zoom", "Zoom", "Zoom"),
        "顯示": x("디스플레이", "Affichage", "Anzeige", "Pantalla", "Schermo", "Tela"),

        // 剪貼簿 / 影像 按鈕
        "貼上": x("붙여넣기", "Coller", "Einsetzen", "Pegar", "Incolla", "Colar"),
        "剪下": x("오려두기", "Couper", "Ausschneiden", "Cortar", "Taglia", "Recortar"),
        "複製": x("복사", "Copier", "Kopieren", "Copiar", "Copia", "Copiar"),
        "選取 ▾": x("선택 ▾", "Sélection ▾", "Auswahl ▾", "Seleccionar ▾", "Seleziona ▾", "Selecionar ▾"),
        "裁剪": x("자르기", "Rogner", "Zuschneiden", "Recortar", "Ritaglia", "Cortar"),
        "重新調整大小": x("크기 조절", "Redimensionner", "Größe ändern", "Cambiar tamaño", "Ridimensiona", "Redimensionar"),
        "重新調整大小…": x("크기 조절…", "Redimensionner…", "Größe ändern …", "Cambiar tamaño…", "Ridimensiona…", "Redimensionar…"),
        "旋轉 ▾": x("회전 ▾", "Rotation ▾", "Drehen ▾", "Girar ▾", "Ruota ▾", "Girar ▾"),

        // 工具 tooltip
        "鉛筆": x("연필", "Crayon", "Bleistift", "Lápiz", "Matita", "Lápis"),
        "以色彩填滿": x("색 채우기", "Remplissage", "Füllen mit Farbe", "Relleno con color", "Riempi con colore", "Preencher com cor"),
        "文字": x("텍스트", "Texte", "Text", "Texto", "Testo", "Texto"),
        "橡皮擦": x("지우개", "Gomme", "Radierer", "Borrador", "Gomma", "Borracha"),
        "色彩選擇工具": x("색 선택", "Pipette", "Farbauswahl", "Selector de color", "Selettore colore", "Seletor de cor"),
        "放大鏡": x("돋보기", "Loupe", "Lupe", "Lupa", "Lente", "Lupa"),

        // 筆刷
        "筆刷 ▾": x("브러시 ▾", "Pinceaux ▾", "Pinsel ▾", "Pinceles ▾", "Pennelli ▾", "Pincéis ▾"),
        "書法筆 1": x("서예 브러시 1", "Calligraphie 1", "Kalligrafie 1", "Caligrafía 1", "Calligrafia 1", "Caligrafia 1"),
        "書法筆 2": x("서예 브러시 2", "Calligraphie 2", "Kalligrafie 2", "Caligrafía 2", "Calligrafia 2", "Caligrafia 2"),
        "噴槍": x("에어브러시", "Aérographe", "Airbrush", "Aerógrafo", "Aerografo", "Aerógrafo"),
        "油畫筆刷": x("유화 브러시", "Pinceau à huile", "Ölpinsel", "Pincel de óleo", "Pennello a olio", "Pincel a óleo"),
        "蠟筆": x("크레용", "Craie grasse", "Wachsmalstift", "Crayón", "Pastello", "Giz de cera"),
        "麥克筆": x("마커", "Marqueur", "Marker", "Marcador", "Evidenziatore", "Marcador"),
        "自然鉛筆": x("자연스러운 연필", "Crayon naturel", "Natürlicher Bleistift", "Lápiz natural", "Matita naturale", "Lápis natural"),
        "水彩筆刷": x("수채화 브러시", "Aquarelle", "Aquarellpinsel", "Acuarela", "Acquerello", "Aquarela"),

        // 形狀 tooltip
        "線條": x("선", "Ligne", "Linie", "Línea", "Linea", "Linha"),
        "曲線": x("곡선", "Courbe", "Kurve", "Curva", "Curva", "Curva"),
        "橢圓形": x("타원", "Ellipse", "Ellipse", "Elipse", "Ellisse", "Elipse"),
        "矩形": x("사각형", "Rectangle", "Rechteck", "Rectángulo", "Rettangolo", "Retângulo"),
        "圓角矩形": x("둥근 사각형", "Rectangle arrondi", "Abgerundetes Rechteck", "Rectángulo redondeado", "Rettangolo arrotondato", "Retângulo arredondado"),
        "多邊形": x("다각형", "Polygone", "Polygon", "Polígono", "Poligono", "Polígono"),
        "三角形": x("삼각형", "Triangle", "Dreieck", "Triángulo", "Triangolo", "Triângulo"),
        "直角三角形": x("직각 삼각형", "Triangle rectangle", "Rechtwinkliges Dreieck", "Triángulo rectángulo", "Triangolo rettangolo", "Triângulo retângulo"),
        "菱形": x("다이아몬드", "Losange", "Raute", "Rombo", "Rombo", "Losango"),
        "五邊形": x("오각형", "Pentagone", "Fünfeck", "Pentágono", "Pentagono", "Pentágono"),
        "六邊形": x("육각형", "Hexagone", "Sechseck", "Hexágono", "Esagono", "Hexágono"),
        "右箭頭": x("오른쪽 화살표", "Flèche droite", "Pfeil nach rechts", "Flecha derecha", "Freccia destra", "Seta para a direita"),
        "左箭頭": x("왼쪽 화살표", "Flèche gauche", "Pfeil nach links", "Flecha izquierda", "Freccia sinistra", "Seta para a esquerda"),
        "上箭頭": x("위쪽 화살표", "Flèche haut", "Pfeil nach oben", "Flecha arriba", "Freccia su", "Seta para cima"),
        "下箭頭": x("아래쪽 화살표", "Flèche bas", "Pfeil nach unten", "Flecha abajo", "Freccia giù", "Seta para baixo"),
        "四角星": x("4각 별", "Étoile à 4 branches", "4-zackiger Stern", "Estrella de 4 puntas", "Stella a 4 punte", "Estrela de 4 pontas"),
        "五角星": x("5각 별", "Étoile à 5 branches", "5-zackiger Stern", "Estrella de 5 puntas", "Stella a 5 punte", "Estrela de 5 pontas"),
        "六角星": x("6각 별", "Étoile à 6 branches", "6-zackiger Stern", "Estrella de 6 puntas", "Stella a 6 punte", "Estrela de 6 pontas"),
        "矩形圖說文字": x("사각형 설명선", "Bulle rectangulaire", "Rechteckige Legende", "Globo rectangular", "Fumetto rettangolare", "Balão retangular"),
        "橢圓形圖說文字": x("타원형 설명선", "Bulle ovale", "Ovale Legende", "Globo ovalado", "Fumetto ovale", "Balão oval"),
        "雲朵圖說文字": x("구름 설명선", "Bulle nuage", "Wolkenlegende", "Globo de nube", "Fumetto a nuvola", "Balão de nuvem"),
        "愛心": x("하트", "Cœur", "Herz", "Corazón", "Cuore", "Coração"),
        "閃電": x("번개", "Éclair", "Blitz", "Rayo", "Fulmine", "Raio"),

        // 外框 / 填滿（下拉選單寬度有限，用短字）
        "外框: 純色": x("윤곽선: 단색", "Contour : uni", "Kontur: voll", "Contorno: sólido", "Contorno: pieno", "Contorno: sólido"),
        "外框: 無外框": x("윤곽선: 없음", "Contour : aucun", "Kontur: keine", "Contorno: ninguno", "Contorno: nessuno", "Contorno: nenhum"),
        "填滿: 無填滿": x("채우기: 없음", "Remplir : aucun", "Füllung: keine", "Relleno: ninguno", "Riempi: nessuno", "Preench.: nada"),
        "填滿: 純色": x("채우기: 단색", "Remplir : uni", "Füllung: voll", "Relleno: sólido", "Riempi: pieno", "Preench.: sólido"),

        // 選取選單
        "矩形選取": x("사각형 선택", "Sélection rectangulaire", "Rechteckige Auswahl", "Selección rectangular", "Selezione rettangolare", "Seleção retangular"),
        "任意形狀選取": x("자유형 선택", "Sélection libre", "Freihandauswahl", "Selección de forma libre", "Selezione a mano libera", "Seleção livre"),
        "全選": x("전체 선택", "Tout sélectionner", "Alles auswählen", "Seleccionar todo", "Seleziona tutto", "Selecionar tudo"),

        // 大小 / 色彩
        "大小 ▾": x("크기 ▾", "Taille ▾", "Größe ▾", "Tamaño ▾", "Dimensioni ▾", "Tamanho ▾"),
        "系統字體": x("시스템 서체", "Police système", "Systemschrift", "Fuente del sistema", "Font di sistema", "Fonte do sistema"),
        "編輯色彩": x("색 편집", "Modifier les couleurs", "Farben bearbeiten", "Editar colores", "Modifica colori", "Editar cores"),
        "色彩 1": x("색 1", "Couleur 1", "Farbe 1", "Color 1", "Colore 1", "Cor 1"),
        "色彩 2": x("색 2", "Couleur 2", "Farbe 2", "Color 2", "Colore 2", "Cor 2"),

        // 檢視
        "放大": x("확대", "Zoom avant", "Vergrößern", "Ampliar", "Ingrandisci", "Ampliar"),
        "縮小": x("축소", "Zoom arrière", "Verkleinern", "Reducir", "Riduci", "Reduzir"),
        "全螢幕": x("전체 화면", "Plein écran", "Vollbild", "Pantalla completa", "Schermo intero", "Tela cheia"),
        "尺規": x("눈금자", "Règles", "Lineale", "Reglas", "Righelli", "Réguas"),
        "格線": x("격자", "Quadrillage", "Gitternetz", "Cuadrícula", "Griglia", "Linhas de grade"),
        "狀態列": x("상태 막대", "Barre d’état", "Statusleiste", "Barra de estado", "Barra di stato", "Barra de status"),

        // 檔案/編輯/影像 選單
        "新增": x("신규", "Nouveau", "Neu", "Nuevo", "Nuovo", "Novo"),
        "開啟…": x("열기…", "Ouvrir…", "Öffnen …", "Abrir…", "Apri…", "Abrir…"),
        "儲存": x("저장", "Enregistrer", "Sichern", "Guardar", "Salva", "Salvar"),
        "另存新檔…": x("다른 이름으로 저장…", "Enregistrer sous…", "Sichern unter …", "Guardar como…", "Salva con nome…", "Salvar como…"),
        "列印…": x("프린트…", "Imprimer…", "Drucken …", "Imprimir…", "Stampa…", "Imprimir…"),
        "內容…": x("속성…", "Propriétés…", "Eigenschaften …", "Propiedades…", "Proprietà…", "Propriedades…"),
        "復原": x("실행 취소", "Annuler", "Widerrufen", "Deshacer", "Annulla", "Desfazer"),
        "取消復原": x("실행 복귀", "Rétablir", "Wiederholen", "Rehacer", "Ripeti", "Refazer"),
        "刪除": x("삭제", "Supprimer", "Löschen", "Eliminar", "Elimina", "Apagar"),
        "向右旋轉 90°": x("오른쪽으로 90° 회전", "Rotation à droite de 90°", "90° nach rechts drehen", "Girar 90° a la derecha", "Ruota a destra di 90°", "Girar 90° à direita"),
        "向左旋轉 90°": x("왼쪽으로 90° 회전", "Rotation à gauche de 90°", "90° nach links drehen", "Girar 90° a la izquierda", "Ruota a sinistra di 90°", "Girar 90° à esquerda"),
        "旋轉 180°": x("180° 회전", "Rotation de 180°", "180° drehen", "Girar 180°", "Ruota di 180°", "Girar 180°"),
        "水平翻轉": x("수평으로 뒤집기", "Retourner horizontalement", "Horizontal spiegeln", "Voltear horizontalmente", "Capovolgi orizzontalmente", "Inverter horizontalmente"),
        "垂直翻轉": x("수직으로 뒤집기", "Retourner verticalement", "Vertikal spiegeln", "Voltear verticalmente", "Capovolgi verticalmente", "Inverter verticalmente"),

        // 對話框
        "影像內容": x("이미지 속성", "Propriétés de l’image", "Bildeigenschaften", "Propiedades de la imagen", "Proprietà immagine", "Propriedades da imagem"),
        "寬度 (像素):": x("너비(픽셀):", "Largeur (pixels) :", "Breite (Pixel):", "Ancho (píxeles):", "Larghezza (pixel):", "Largura (pixels):"),
        "高度 (像素):": x("높이(픽셀):", "Hauteur (pixels) :", "Höhe (Pixel):", "Alto (píxeles):", "Altezza (pixel):", "Altura (pixels):"),
        "維持外觀比例": x("종횡비 유지", "Conserver les proportions", "Seitenverhältnis beibehalten", "Mantener proporción", "Mantieni proporzioni", "Manter proporção"),
        "確定": x("확인", "OK", "OK", "Aceptar", "OK", "OK"),
        "取消": x("취소", "Annuler", "Abbrechen", "Cancelar", "Annulla", "Cancelar"),
        "不要儲存": x("저장 안 함", "Ne pas enregistrer", "Nicht sichern", "No guardar", "Non salvare", "Não salvar"),
        "檔案格式:": x("파일 포맷:", "Format :", "Format:", "Formato:", "Formato:", "Formato:"),
        "字型": x("서체", "Police", "Schrift", "Fuente", "Font", "Fonte"),
        "字級": x("크기", "Taille", "Größe", "Tamaño", "Dimensione", "Tamanho"),
        "粗體": x("굵게", "Gras", "Fett", "Negrita", "Grassetto", "Negrito"),
        "斜體": x("기울임꼴", "Italique", "Kursiv", "Cursiva", "Corsivo", "Itálico"),
        "底線": x("밑줄", "Souligné", "Unterstrichen", "Subrayado", "Sottolineato", "Sublinhado"),

        // tooltip 說明
        "油漆桶容許度：越高，越多相近顏色會被一起填滿": x(
            "채우기 허용 오차: 높을수록 비슷한 색이 함께 채워집니다",
            "Tolérance du remplissage : plus elle est élevée, plus les couleurs proches sont remplies",
            "Fülltoleranz: je höher, desto mehr ähnliche Farben werden gefüllt",
            "Tolerancia de relleno: cuanto mayor, más colores similares se rellenan",
            "Tolleranza riempimento: più è alta, più colori simili vengono riempiti",
            "Tolerância de preenchimento: quanto maior, mais cores semelhantes são preenchidas"),
        "透明色：以此繪圖會清成透明（PNG 會保留透明）": x(
            "투명 색: 이 색으로 그리면 투명해집니다(PNG에서 유지)",
            "Couleur transparente : dessiner avec la rend transparent (conservé en PNG)",
            "Transparente Farbe: Malen damit macht transparent (bleibt in PNG erhalten)",
            "Color transparente: dibujar con él deja transparencia (se conserva en PNG)",
            "Colore trasparente: disegnando si ottiene trasparenza (mantenuta nei PNG)",
            "Cor transparente: desenhar com ela deixa transparente (mantido em PNG)"),
    ]
}
