USE CISP_SHARED

-- SEED: ACCOUNTS_LEVELS
IF NOT EXISTS(SELECT 1 FROM ACCOUNTS_LEVELS)
INSERT INTO ACCOUNTS_LEVELS(ACCOUNT_LEVEL_ID, NAME) VALUES
(1, 'ДСП'),
(2, 'КТ')
GO

-- SEED: AGENTS_CATEGORIES
;SET IDENTITY_INSERT AGENTS_CATEGORIES ON;
IF NOT EXISTS(SELECT 1 FROM AGENTS_CATEGORIES)
INSERT INTO AGENTS_CATEGORIES(CATEGORY_ID, NAME, IS_DELETED) VALUES
(0, '<нет>', 0),
(1, 'VIP', 1),
(2, 'Арбитраж', 1),
(3, 'Зона риска', 1),
(4, 'Лояльный клиент', 0),
(5, 'Норма', 0),
(6, 'Черный список', 0),
(7, 'Новая строка', 1),
(8, 'Новая строка', 1),
(9, 'Новая строка', 1),
(10, 'Новая строка', 1)
;SET IDENTITY_INSERT AGENTS_CATEGORIES OFF;
GO

-- SEED: AGENTS_STATUSES
;SET IDENTITY_INSERT AGENTS_STATUSES ON;
IF NOT EXISTS(SELECT 1 FROM AGENTS_STATUSES)
INSERT INTO AGENTS_STATUSES(STATUS_ID, NAME, IS_DELETED) VALUES
(-2, 'Ликвидировано', 0),
(-1, 'Удалено', 0),
(0, 'Черновик', 0),
(1, 'Действует', 0),
(10, 'Архив', 0)
;SET IDENTITY_INSERT AGENTS_STATUSES OFF;
GO

-- SEED: BDR_ARTICLES_STATUSES
IF NOT EXISTS(SELECT 1 FROM BDR_ARTICLES_STATUSES)
INSERT INTO BDR_ARTICLES_STATUSES(STATUS_ID, NAME) VALUES
(0, 'Черновик'),
(1, 'Принят')
GO

-- SEED: BDR_PERIODS_TYPES
IF NOT EXISTS(SELECT 1 FROM BDR_PERIODS_TYPES)
INSERT INTO BDR_PERIODS_TYPES(TYPE_ID, NAME) VALUES
(2, 'месяц'),
(3, 'квартал'),
(4, 'полугодие'),
(5, 'год')
GO

-- SEED: BUDGETS_STATUSES
IF NOT EXISTS(SELECT 1 FROM BUDGETS_STATUSES)
INSERT INTO BUDGETS_STATUSES(STATUS_ID, NAME) VALUES
(-1, 'Удалено'),
(0, 'Черновик'),
(1, 'Открыт'),
(2, 'Закрыт')
GO

-- SEED: BUDGETS_TYPES
IF NOT EXISTS(SELECT 1 FROM BUDGETS_TYPES)
INSERT INTO BUDGETS_TYPES(TYPE_ID, NAME) VALUES
(0, 'Общий'),
(1, 'Проекты'),
(2, 'Проекты (WBS)'),
(3, 'Проекты (сделки)'),
(4, 'Операционный')
GO

-- SEED: CCY
IF NOT EXISTS(SELECT 1 FROM CCY)
INSERT INTO CCY(CCY_ID, NAME, NAME_RUB, NAME_KOP, CODE) VALUES
('AED', 'AED', null, null, 9),
('CHF', 'CHF', null, null, 5),
('CNY', 'CNY', null, null, 6),
('EUR', 'EUR', null, null, 3),
('GBP', 'GBP', null, null, 4),
('KZT', 'KZT', null, null, 7),
('RUR', 'RUR', null, null, 1),
('TRY', 'TRY', null, null, 8),
('USD', 'USD', null, null, 2)
GO

-- SEED: CITIES
IF NOT EXISTS(SELECT 1 FROM CITIES)
INSERT INTO CITIES(CITY_ID, NAME) VALUES
(0, '<не указан>'),
(1, 'Барнаул'),
(2, 'Волгоград'),
(3, 'Воронеж'),
(4, 'Екатеринбург'),
(5, 'Иркутск'),
(6, 'Красногорск'),
(7, 'Краснодар'),
(8, 'Красноярск'),
(9, 'Москва'),
(10, 'Нижний Новгород'),
(11, 'Новосибирск'),
(12, 'Омск'),
(13, 'Пермь'),
(14, 'Ростов'),
(15, 'Самара'),
(16, 'Санкт-Петербург'),
(17, 'Саратов'),
(18, 'Тюмень'),
(19, 'Уфа'),
(20, 'Челябинск'),
(21, 'Брянск'),
(22, 'Белгород'),
(23, 'Вологда'),
(24, 'Смоленск'),
(25, 'Пятигорск'),
(26, 'Пенза'),
(27, 'Казань'),
(28, 'Киев'),
(29, 'Минск'),
(30, 'Ташкент'),
(31, 'Душанбе'),
(32, 'Алматы'),
(33, 'Калининград'),
(34, 'Фергана'),
(35, 'Людиново'),
(36, 'Киров'),
(37, 'Гурьевск'),
(38, 'Рига'),
(39, 'Калуга'),
(41, 'Луганск'),
(42, 'СИТИ (под С-ПБ)'),
(43, 'Шымкент'),
(44, 'Андижан'),
(45, 'Самарканд'),
(46, 'Бишкек'),
(54, 'Афонасово'),
(55, 'Барятино'),
(56, 'Игнатовка'),
(57, 'Б.Савки'),
(58, 'М.Савки'),
(59, 'Космачево'),
(60, 'Асмолово'),
(61, 'Хабаровск'),
(62, 'Липецк'),
(63, 'Ульяновск'),
(64, 'Саранск'),
(65, 'Ижевск'),
(66, 'Ярославль'),
(67, 'Новокузнецк'),
(68, 'Донецк'),
(69, 'Астана'),
(70, 'Оренбург'),
(71, 'Псков'),
(72, 'Курган'),
(73, 'Жиздра'),
(74, 'Симферополь'),
(75, 'Сафоново'),
(76, 'Владимир'),
(77, 'Кашира')
GO

-- SEED: COUNTRIES
;SET IDENTITY_INSERT COUNTRIES ON;
IF NOT EXISTS(SELECT 1 FROM COUNTRIES)
INSERT INTO COUNTRIES(COUNTRY_ID, NAME) VALUES
(1, 'Россия'),
(2, 'Беларусь'),
(3, 'Украина'),
(4, 'Азербайджан'),
(5, 'Армения'),
(6, 'Афганистан'),
(7, 'Бангладеш'),
(8, 'Бахрейн'),
(9, 'Бруней'),
(10, 'Бутан'),
(11, 'Восточный Тимор'),
(12, 'Вьетнам'),
(13, 'Грузия'),
(14, 'Израиль'),
(15, 'Индия'),
(16, 'Индонезия'),
(17, 'Иордания'),
(18, 'Ирак'),
(19, 'Иран'),
(20, 'Йемен'),
(21, 'Казахстан'),
(22, 'Узбекистан'),
(23, 'Камбоджа'),
(24, 'Катар'),
(25, 'Кипр'),
(26, 'Киргизия'),
(27, 'КНДР'),
(28, 'Китай'),
(29, 'Кувейт'),
(30, 'Лаос'),
(31, 'Ливан'),
(32, 'Малайзия'),
(33, 'Мальдивы'),
(34, 'Монголия'),
(35, 'Непал'),
(36, 'ОАЭ'),
(37, 'Оман'),
(38, 'Пакистан'),
(39, 'Палестина'),
(40, 'Саудовская Аравия'),
(41, 'Сингапур'),
(42, 'Сирия'),
(43, 'Таджикистан'),
(44, 'Таиланд'),
(45, 'Туркменистан'),
(46, 'Турция'),
(47, 'Филиппины'),
(48, 'Шри-Ланка'),
(49, 'Южная Корея'),
(50, 'Япония'),
(51, 'Алжир'),
(52, 'Ангола'),
(53, 'Бенин'),
(54, 'Ботсвана'),
(55, 'Буркина-Фасо'),
(56, 'Бурунди'),
(57, 'Габон'),
(58, 'Гамбия'),
(59, 'Гана'),
(60, 'Гвинея'),
(61, 'Гвинея-Бисау'),
(62, 'Джибути'),
(63, 'Египет'),
(64, 'Замбия'),
(65, 'Западная Сахара'),
(66, 'Зимбабве'),
(67, 'Кабо-Верде'),
(68, 'Кот-д`Ивуар'),
(69, 'Камерун'),
(70, 'Кения'),
(71, 'Коморские острова'),
(72, 'Демократическая Республика Конго'),
(73, 'Народная Республика Конго'),
(74, 'Лесото'),
(75, 'Либерия'),
(76, 'Ливия'),
(77, 'Маврикий'),
(78, 'Мавритания'),
(79, 'Мадагаскар'),
(80, 'Майотта'),
(81, 'Малави'),
(82, 'Мали'),
(83, 'Марокко'),
(84, 'Мозамбик'),
(85, 'Намибия'),
(86, 'Нигер'),
(87, 'Нигерия'),
(88, 'Реюньон'),
(89, 'Руанда'),
(90, 'Сан-Томе и Принсипи'),
(91, 'Свазиленд'),
(92, 'Святой Елены Остров'),
(93, 'Сейшельские острова'),
(94, 'Сенегал'),
(95, '«Сеута и Мелилья» Испания'),
(96, 'Сомали'),
(97, 'Судан'),
(98, 'Сьерра-Леоне'),
(99, 'Танзания'),
(100, 'Того'),
(101, 'Тунис'),
(102, 'Уганда'),
(103, 'ЧАД'),
(104, 'Центрально-Африканская республика'),
(105, 'Экваториальная Гвинея'),
(106, 'Эритрея'),
(107, 'Эфиопия'),
(108, 'ЮАР'),
(109, 'Австрия'),
(110, 'Андорра'),
(111, 'Албания'),
(112, 'Бельгия'),
(113, 'Болгария'),
(114, 'Босния и Герцеговина'),
(115, 'Ватикан'),
(116, 'Великобритания'),
(117, 'Венгрия'),
(118, 'Германия'),
(119, 'Гибралтар'),
(120, 'Греция'),
(121, 'Дания'),
(122, 'Ирландия'),
(123, 'Исландия'),
(124, 'Испания'),
(125, 'Италия'),
(126, 'Латвия'),
(127, 'Литва'),
(128, 'Лихтенштейн'),
(129, 'Люксембург'),
(130, 'Македония'),
(131, 'Мальта'),
(132, 'Молдавия'),
(133, 'Монако'),
(134, 'Нидерланды'),
(135, 'Норвегия'),
(136, 'Польша'),
(137, 'Португалия'),
(138, 'Румыния'),
(139, 'Сан-Марино'),
(140, 'Сербия и Черногория'),
(141, 'Словакия'),
(142, 'Словения'),
(143, 'Фарерские острова'),
(144, 'Финляндия'),
(145, 'Франция'),
(146, 'Хорватия'),
(147, 'Черногория'),
(148, 'Чехия'),
(149, 'Швейцария'),
(150, 'Швеция'),
(151, 'Эстония'),
(152, 'Австралия'),
(153, 'Вануату'),
(154, 'Гуам'),
(155, 'Восточное (Американское) Самоа'),
(156, 'Западное Самоа'),
(157, 'Кирибати'),
(158, 'Кокосовые острова'),
(159, 'Кука острова'),
(160, 'Маршаловы острова'),
(161, 'Мидуэй'),
(162, 'Микронезия'),
(163, 'Науру'),
(164, 'Ниуэ'),
(165, 'Новая Зеландия'),
(166, 'Новая Каледония'),
(167, 'Норфолк'),
(168, 'Палау'),
(169, 'Папуа-Новая Гвинея'),
(170, 'Питкэрн'),
(171, 'Рождества остров'),
(172, 'Северные Марианские острова'),
(173, 'Токелау'),
(174, 'Тонга'),
(175, 'Тувалу'),
(176, 'Уоллис и Футуна'),
(177, 'Уэйк'),
(178, 'Фиджи'),
(179, 'Гренландия'),
(180, 'Канада'),
(181, 'Мексика'),
(182, 'Сен-Пьер и Микелон'),
(183, 'США'),
(184, 'Ангилья (Ангуилла)'),
(185, 'Антигуа и Барбуда'),
(186, 'Нидерландские Антиллы'),
(187, 'Аруба'),
(188, 'Багамские острова'),
(189, 'Барбадос'),
(190, 'Белиз'),
(191, 'Бермудские острова'),
(192, 'Британские Виргинские острова'),
(193, 'Виргинские острова'),
(194, 'Гаити'),
(195, 'Гваделупа'),
(196, 'Гватемала'),
(197, 'Гондурас'),
(198, 'Гренада'),
(199, 'Доминика'),
(200, 'Доминиканская республика'),
(201, 'Каймановы острова'),
(202, 'Коста-Рика'),
(203, 'Куба'),
(204, 'Мартиника'),
(205, 'Монтсеррат'),
(206, 'Никарагуа'),
(207, 'Панама'),
(208, 'Пуэрто-Рико'),
(209, 'Сальвадор'),
(210, 'Сент-Винсент и Гренадины'),
(211, 'Сент-Китс и Невис'),
(212, 'Сент-Люсия'),
(213, 'Тёркс и Кайкос'),
(214, 'Тринидад и Тобаго'),
(215, 'Ямайка'),
(216, 'Аргентина'),
(217, 'Боливия'),
(218, 'Бразилия'),
(219, 'Венесуэла'),
(220, 'Гайана'),
(221, 'Колумбия'),
(222, 'Парагвай'),
(223, 'Перу'),
(224, 'Суринам'),
(225, 'Уругвай'),
(226, 'Фолклендские (Мальвинские) острова'),
(227, 'Чили'),
(228, 'Эквадор')
;SET IDENTITY_INSERT COUNTRIES OFF;
GO

-- SEED: DEALS_CREDITS_MOVES_TYPES
IF NOT EXISTS(SELECT 1 FROM DEALS_CREDITS_MOVES_TYPES)
INSERT INTO DEALS_CREDITS_MOVES_TYPES(MOVE_TYPE_ID, NAME) VALUES
(1, 'ВхОст'),
(2, 'Приход'),
(3, 'Расход')
GO

-- SEED: DEALS_DOCS_TYPES
IF NOT EXISTS(SELECT 1 FROM DEALS_DOCS_TYPES)
INSERT INTO DEALS_DOCS_TYPES(TYPE_ID, NAME) VALUES
(1, 'Договора с принципалом'),
(2, 'Договора с контрагентами')
GO

-- SEED: DOCUMENTS_DICT_RESPONSIBLES
;SET IDENTITY_INSERT DOCUMENTS_DICT_RESPONSIBLES ON;
IF NOT EXISTS(SELECT 1 FROM DOCUMENTS_DICT_RESPONSIBLES)
INSERT INTO DOCUMENTS_DICT_RESPONSIBLES(TENANT_ID, RESPONSIBLE_ID, NAME, SHORT_NAME, NOTE, ADD_DATE) VALUES
(1, 1, 'Руководитель', 'chief', 'Непосредственный руководитель', '2018-02-10 23:25:01'),
(1, 2, 'Руководитель проекта', 'prj_chief', 'Руководитель проекта', '2018-02-10 23:25:01'),
(1, 3, 'Куратор проекта', 'prj_curator', 'Куратор проекта', '2018-02-10 23:25:01')
;SET IDENTITY_INSERT DOCUMENTS_DICT_RESPONSIBLES OFF;
GO

-- SEED: DOCUMENTS_DICT_ROUTES
;SET IDENTITY_INSERT DOCUMENTS_DICT_ROUTES ON;
IF NOT EXISTS(SELECT 1 FROM DOCUMENTS_DICT_ROUTES)
INSERT INTO DOCUMENTS_DICT_ROUTES(TENANT_ID, DICT_ROUTE_ID, NAME, NOTE, ADD_DATE, IS_DELETED) VALUES
(1, 1, 'Команда проекта', 'Участники,  указанные в проекте', '2018-02-10 23:25:01', 0)
;SET IDENTITY_INSERT DOCUMENTS_DICT_ROUTES OFF;
GO

-- SEED: DOCUMENTS_STATUSES
IF NOT EXISTS(SELECT 1 FROM DOCUMENTS_STATUSES)
INSERT INTO DOCUMENTS_STATUSES(STATUS_ID, NAME) VALUES
(-2, 'Истёк срок действия'),
(-1, 'Удалено'),
(0, 'Черновик'),
(1, 'Отправлено'),
(2, 'Согласование'),
(3, 'Согласовано'),
(10, 'Принят')
GO

-- SEED: DOCUMENTS_TYPES
IF NOT EXISTS(SELECT 1 FROM DOCUMENTS_TYPES)
INSERT INTO DOCUMENTS_TYPES(TYPE_ID, NAME) VALUES
(1, 'Документ'),
(2, 'Договорные документы')
GO

-- SEED: EVENTS_FEEDS_TYPES
;SET IDENTITY_INSERT EVENTS_FEEDS_TYPES ON;
IF NOT EXISTS(SELECT 1 FROM EVENTS_FEEDS_TYPES)
INSERT INTO EVENTS_FEEDS_TYPES(FEED_ID, FEED_TYPE_ID, NAME, SHORT_NAME, DESCRIPTION, IS_ALERT) VALUES
(2, 1, 'Завершение операции проекта', 'completed', null, 1),
(2, 2, 'Добавление комментария', 'comment', null, null),
(2, 3, 'Сдвиг сроков проекта', 'shift', null, null),
(3, 5, 'Заверешение задач на этой неделе', 'thisweek', null, 1),
(3, 6, 'Просроченные задачи', 'overdue', null, 1),
(3, 7, 'Эскалация просроченных задач руководителю', 'overdue.escalate.chief', null, 1),
(2, 8, 'Операции текущей недели', 'project.task.thisweek', null, 1),
(2, 9, 'Просроченные операции', 'project.task.overdue', null, 1),
(2, 11, 'Просроченные отчёты по рискам', 'overdue.risks', null, 1)
;SET IDENTITY_INSERT EVENTS_FEEDS_TYPES OFF;
GO

-- SEED: EVENTS_FEEDS
;SET IDENTITY_INSERT EVENTS_FEEDS ON;
IF NOT EXISTS(SELECT 1 FROM EVENTS_FEEDS)
INSERT INTO EVENTS_FEEDS(FEED_ID, NAME, DESCRIPTION, IS_DELETED) VALUES
(-1, 'Системные', null, 0),
(1, 'Новости', null, 0),
(2, 'Проекты', null, 0),
(3, 'Задачи', null, 0),
(100, 'Прочие', null, 0)
;SET IDENTITY_INSERT EVENTS_FEEDS OFF;
GO

-- SEED: EVENTS_PRIORITIES
IF NOT EXISTS(SELECT 1 FROM EVENTS_PRIORITIES)
INSERT INTO EVENTS_PRIORITIES(PRIORITY_ID, NAME, CSS_CLASS) VALUES
(1, 'Важное', 'fa fa-info-circle'),
(2, 'Критичное', 'fa fa-exclamation-circle')
GO

-- SEED: EVENTS_STATUSES
;SET IDENTITY_INSERT EVENTS_STATUSES ON;
IF NOT EXISTS(SELECT 1 FROM EVENTS_STATUSES)
INSERT INTO EVENTS_STATUSES(STATUS_ID, NAME, IS_DELETED) VALUES
(-1, 'Удалено', 0),
(0, 'Черновик', 0),
(1, 'Опубликовано', 0),
(10, 'Архив', 0)
;SET IDENTITY_INSERT EVENTS_STATUSES OFF;
GO

-- SEED: FILE_TYPES_ICONS
IF NOT EXISTS(SELECT 1 FROM FILE_TYPES_ICONS)
INSERT INTO FILE_TYPES_ICONS(EXTENSION, NAME, IMG_URL) VALUES
('7z', 'WinZIP архив', 'zip.gif'),
('avi', 'Видео', 'avi.png'),
('bmp', 'Иллюстрация BMP', 'png.gif'),
('cispdoc', 'Документ КИСП', 'cispdoc.png'),
('doc', 'Документ Microsoft Word', 'word.gif'),
('docx', 'Документ Microsoft Word', 'word.gif'),
('eml', 'Электронное письмо', 'eml.gif'),
('exe', 'ВНИМАНИЕ! Выполняемая программа', 'exe.gif'),
('gif', 'Иллюстрация GIF', 'png.gif'),
('gz', 'Архив', 'zip.gif'),
('htm', 'HTML документ', 'html.gif'),
('html', 'HTML документ', 'html.gif'),
('jpeg', 'Иллюстрация JPEG', 'png.gif'),
('jpg', 'Иллюстрация JPEG', 'png.gif'),
('mpp', 'Документ Microsoft Project', 'mpp.gif'),
('pdf', 'Adobe Acrobat документ', 'pdf.gif'),
('png', 'Иллюстрация PNG', 'png.gif'),
('pps', 'Презентация', 'pps.gif'),
('ppt', 'Презентация', 'pps.gif'),
('psd', 'Документ Adobe Photoshop', 'psd.gif'),
('rar', 'WinRAR архив', 'zip.gif'),
('rtf', 'Документ Microsoft Word RTF', 'rtf.gif'),
('tif', 'Иллюстрация TIFF', 'tiff.gif'),
('tiff', 'Иллюстрация TIFF', 'tiff.gif'),
('txt', 'Текстовый документ', 'txt.gif'),
('xls', 'Документ Microsoft Excel', 'xls.gif'),
('xlsx', 'Документ Microsoft Excel', 'xls.gif'),
('xml', 'XML документ', 'xml.gif'),
('zip', 'WinZIP архив', 'zip.gif')
GO

-- SEED: FIN_GOALS_STATUSES
IF NOT EXISTS(SELECT 1 FROM FIN_GOALS_STATUSES)
INSERT INTO FIN_GOALS_STATUSES(STATUS_ID, NAME) VALUES
(-2, 'Скрыто'),
(-1, 'Удалено'),
(1, 'Открыто'),
(2, 'Закрыто')
GO

-- SEED: FINDOCS_STATUSES
IF NOT EXISTS(SELECT 1 FROM FINDOCS_STATUSES)
INSERT INTO FINDOCS_STATUSES(STATUS_ID, NAME) VALUES
(0, 'Черновик'),
(1, 'Принят'),
(2, 'Включен')
GO

-- SEED: FINDOCS_TAGS_STATUSES
IF NOT EXISTS(SELECT 1 FROM FINDOCS_TAGS_STATUSES)
INSERT INTO FINDOCS_TAGS_STATUSES(STATUS_ID, NAME) VALUES
(0, 'системный'),
(1, 'открыто'),
(2, 'закрыто')
GO

-- SEED: MFR_EQUIPMENTS_STATUSES
IF NOT EXISTS(SELECT 1 FROM MFR_EQUIPMENTS_STATUSES)
INSERT INTO MFR_EQUIPMENTS_STATUSES(STATUS_ID, NAME) VALUES
(-1, 'Удалено'),
(0, 'Черновик'),
(10, 'Принят')
GO

-- SEED: MFR_EXT_PROBABILITIES
IF NOT EXISTS(SELECT 1 FROM MFR_EXT_PROBABILITIES)
INSERT INTO MFR_EXT_PROBABILITIES(PROBABILITY_ID, NAME, STYLE) VALUES
(1, 'Вероятность 80%', 'background-color: lightcoral'),
(2, 'Вероятность 90%', 'background-color: lightskyblue'),
(3, 'Вероятность >95%', 'background-color: cornflowerblue')
GO

-- SEED: MFR_EXT_STATUSES
IF NOT EXISTS(SELECT 1 FROM MFR_EXT_STATUSES)
INSERT INTO MFR_EXT_STATUSES(STATUS_ID, NAME) VALUES
(-100, 'Архив'),
(-99, 'Отменён'),
(0, 'Черновик'),
(1, 'Открыт')
GO

-- SEED: MFR_EXT_TYPES
IF NOT EXISTS(SELECT 1 FROM MFR_EXT_TYPES)
INSERT INTO MFR_EXT_TYPES(TYPE_ID, NAME) VALUES
(1, 'Прогнозный заказ')
GO

-- SEED: MFR_ITEMS_STATUSES
IF NOT EXISTS(SELECT 1 FROM MFR_ITEMS_STATUSES)
INSERT INTO MFR_ITEMS_STATUSES(STATUS_ID, NAME, NAME_QUEUE, SHORT_NAME, CSS, STYLE, GROUP_NAME, SORT_ID) VALUES
(-2, 'Есть назначения', 'Есть назначение', 'ИСП', 'fa fa-user text-bold', 'color: lightgreen', 'items', 7),
(0, 'Черновик', 'К исполнению', 'Ч', 'fa fa-circle', 'color: black', 'items, materials', 2),
(1, 'В работе', 'Исполняется', 'Р', 'fa fa-circle', 'color: lightgreen; opacity: 0.6;', 'items, materials', 6),
(2, 'Готов к выдаче', 'Готов к назначению', 'ГТ', 'fa fa-circle', 'color: orange', 'items', 4),
(3, 'Запрет', null, 'З', 'fa fa-circle', 'color: red', 'items', 3),
(10, 'Создано', null, 'СОЗД', 'fa fa-circle', 'color: cornflowerblue', 'items', 5),
(20, 'Заявка', null, 'З', 'fa fa-circle', 'color: darkgoldenrod', 'materials', 20),
(25, 'Счёт', null, 'Счёт', 'fa fa-circle', 'color: orange', 'materials', 25),
(30, 'Приход', null, 'Прих', 'fa fa-circle', 'color: green', 'materials', 30),
(90, 'ЛЗК', null, 'ЛЗК', 'fa fa-circle', 'color: #007bff', 'materials', 90),
(100, 'Сделано', 'Сделано', '100:', 'fa fa-circle', 'color: lightgray', 'items, materials', 100),
(200, 'Проверка', null, '?', 'fa fa-question-circle', 'color: red', 'items', 200)
GO

-- SEED: MFR_ITEMS_TYPES
;SET IDENTITY_INSERT MFR_ITEMS_TYPES ON;
IF NOT EXISTS(SELECT 1 FROM MFR_ITEMS_TYPES)
INSERT INTO MFR_ITEMS_TYPES(GROUP_ID, TYPE_ID, NAME, NOTE, IS_DELETED, ADD_DATE, ADD_MOL_ID, UPDATE_DATE, UPDATE_MOL_ID, SORT_ID) VALUES
(1, 1, 'Изделия', null, 0, '2019-12-02 16:19:55', null, null, null, 1),
(1, 2, 'ВЗЧ', null, 0, '2019-12-02 16:19:55', null, null, null, 2),
(1, 3, 'Сборки', null, 0, '2019-12-02 16:19:55', null, null, null, 3),
(1, 4, 'Детали', null, 0, '2019-12-02 16:19:55', null, null, null, 4),
(1, 5, 'Стандартные изделия', null, 0, '2019-12-02 16:19:55', null, null, null, 5),
(1, 6, 'Покупные изделия', null, 0, '2019-12-02 16:19:55', null, null, null, 6),
(2, 7, 'Материалы', null, 0, '2019-12-02 16:19:55', null, null, null, 7),
(2, 8, 'Вспомогательные материалы', null, 0, '2019-12-02 16:19:55', null, null, null, 8),
(1, 9, 'Упаковки', null, 0, '2019-12-02 16:19:55', null, null, null, 9),
(3, 12, 'Комплект', null, 0, '2019-12-02 16:19:55', null, null, null, 12),
(1, 51, 'Крепеж', null, 0, '2021-07-02 13:28:29', null, null, null, 51)
;SET IDENTITY_INSERT MFR_ITEMS_TYPES OFF;
GO

-- SEED: MFR_PDM_STATUSES
IF NOT EXISTS(SELECT 1 FROM MFR_PDM_STATUSES)
INSERT INTO MFR_PDM_STATUSES(STATUS_ID, NAME) VALUES
(-1, 'Удалено'),
(0, 'Черновик'),
(1, 'Поручено'),
(2, 'Исполнение'),
(3, 'Исполнено'),
(10, 'Принят'),
(100, 'Защищено')
GO

-- SEED: MFR_PDMS_REGLAMENTS
IF NOT EXISTS(SELECT 1 FROM MFR_PDMS_REGLAMENTS)
INSERT INTO MFR_PDMS_REGLAMENTS(EXEC_REGLAMENT_ID, NAME) VALUES
(1, 'Регл.тех.нормирования'),
(2, 'Регл.труд.нормирования')
GO

-- SEED: MFR_PLANS_JOBS_TYPES
IF NOT EXISTS(SELECT 1 FROM MFR_PLANS_JOBS_TYPES)
INSERT INTO MFR_PLANS_JOBS_TYPES(TYPE_ID, NAME, SHORT_NAME, SLICE) VALUES
(1, 'Сменное задание', 'СЗ', 'component'),
(2, 'ЛЗК', 'ЛЗК', 'material'),
(3, 'Перераспределение материалов', 'ЛЗК-ПМ', 'material'),
(4, 'Инвентаризация', 'ИНВ', 'component'),
(5, 'Кооперация', 'КООП', 'component'),
(6, 'Конструирование', 'КР', 'component'),
(100, 'Вх.остаток', 'ВХ', '-')
GO

-- SEED: MFR_R_PROVIDES_XSLICES
IF NOT EXISTS(SELECT 1 FROM MFR_R_PROVIDES_XSLICES)
INSERT INTO MFR_R_PROVIDES_XSLICES(XSLICE, NAME, NOTE) VALUES
('coop', '8-Кооперация', null),
('deficit', '1-Дефицит', null),
('distrib', '5-Перераспределено', null),
('job', '4-Выдано', null),
('lzk', '3-ЛЗК', null),
('manual', 'Ручная правка', null),
('misc', '7-Прочее', null),
('ship', '2-Остатки (к выдаче)', null),
('stock', '6-Остатки (не связанные)', null)
GO

-- SEED: MFR_SDOCS_PRIORITIES
IF NOT EXISTS(SELECT 1 FROM MFR_SDOCS_PRIORITIES)
INSERT INTO MFR_SDOCS_PRIORITIES(PRIORITY_ID, PRIORITY_MAX, NAME, CSS) VALUES
(0, 99, 'высший', 'badge bg-danger text-xx-small opaque mb-1'),
(100, 199, 'высокий', 'badge bg-primary text-xx-small opaque mb-1'),
(200, 399, 'средний', 'badge bg-secondary text-xx-small opaque mb-1'),
(400, 500, 'низкий', 'badge bg-secondary text-xx-small opaque mb-1')
GO

-- SEED: MFR_PLANS_JOBS_PROBLEMS_TYPES
;SET IDENTITY_INSERT MFR_PLANS_JOBS_PROBLEMS_TYPES ON;
IF NOT EXISTS(SELECT 1 FROM MFR_PLANS_JOBS_PROBLEMS_TYPES)
insert into MFR_PLANS_JOBS_PROBLEMS_TYPES(PROBLEM_ID,NAME,NOTE) values
(1,'Отсутствие инструмента','Указать наименование и количество требуемого инструмента'),
(2,'Отсутствие оснастки','Указать наименование требуемой оснастки, для какой операции'),
(3,'Поломка оборудования','Указать наименование оборудования и узел, вышедший из строя'),
(4,'Отсутствие исполнителя','Указать причину отсутствия: на больничном, дефицит работников…'),
(5,'Ошибка маршрута','Указать номер участка, на который требуется направить деталь'),
(6,'Ошибка длительности','Указать фактическую длительность дней/часов'),
(7,'Оборудование занято',' Указать номер сменного задания, на котором занято оборудование, дату, до которой будет занято оборудование'),
(8,'Исполнитель занят','Указать номер сменного задания, на котором занят исполнитель, дату, до которой будет занят исполнитель'),
(9,'Отсутствие заготовки','Указать номер участка, с которого не передана заготовка'),
(10,'Брак производства','Указать вид барака, дату исправления'),
(11,'Отсутствие ЛЗК','Указать наименование и количество требуемых материалов/комплектующих'),
(12,'В работе','Можно указать дополнительную информацию'),
(13,'Вопросы по изготовлению к УГК/ОГТ',null)
;SET IDENTITY_INSERT MFR_PLANS_JOBS_PROBLEMS_TYPES OFF;

-- SEED: MOLS_STATUSES
IF NOT EXISTS(SELECT 1 FROM MOLS_STATUSES)
INSERT INTO MOLS_STATUSES(STATUS_ID, NAME, SORT, SHORT_NAME, IMG_URL) VALUES
(-2, 'Системный', null, 'sys', '/Img/mol/status_black.gif'),
(-1, 'Заблокирован', null, 'У', '/Img/mol/status_black.gif'),
(0, 'Черновик', null, 'Ч', '/Img/mol/status_test.gif'),
(2, 'Испытательный срок', 1, 'И', '/Img/mol/status_test.gif'),
(3, 'Активен', null, 'Р', '/Img/mol/status_work.gif')
GO

-- SEED: OBJS_FOLDERS_STATUSES
IF NOT EXISTS(SELECT 1 FROM OBJS_FOLDERS_STATUSES)
INSERT INTO OBJS_FOLDERS_STATUSES(STATUS_ID, NAME) VALUES
(0, 'системный'),
(1, 'открыто'),
(2, 'закрыто')
GO

-- SEED: OBJS_TYPES
;SET IDENTITY_INSERT OBJS_TYPES ON;
IF NOT EXISTS(SELECT 1 FROM OBJS_TYPES)
INSERT INTO OBJS_TYPES(TYPE, NAME, DESCRIPTION, SOURCE_CMD, URL, FOLDER_KEYWORD, ADD_DATE, ID, IS_EXPORT, BASE_TABLE, BASE_TABLE_COLUMN) VALUES
('A', 'Контрагенты', null, null, '/agents', 'AGENT', null, 1, null, 'AGENTS', 'AGENT_ID'),
('BDG', 'Бюджеты', null, null, '/finance/budgets', 'BUDGET', null, 2, null, 'BUDGETS', 'BUDGET_ID'),
('BUYORDER', 'Заявки на закупку', null, null, '/finance/lgs/buyorders', 'BUYORDER', '2024-06-04 23:08:56', 132, null, 'SUPPLY_BUYORDERS', 'DOC_ID'),
('DL', 'Сделки', null, null, '/finance/deals', 'DEALS', null, 3, 1, 'DEALS', 'DEAL_ID'),
('DOC', 'Документы', null, null, '/documents', 'DOCUMENT', null, 4, null, 'DOCUMENTS', 'DOCUMENT_ID'),
('F', 'Папки', null, null, null, null, null, 5, null, null, null),
('FD', 'Оплаты', null, null, '/finance/findocs', 'FINDOC', null, 6, 1, 'FINDOCS', 'FINDOC_ID'),
('INV', 'Счета поставщиков', null, null, '/finance/lgs/invoices', 'INVOICE', '2021-08-06 16:26:22', 30, null, 'SUPPLY_INVOICES', 'DOC_ID'),
('INVPAY', 'Счета и оплаты', null, null, '/finance/lgs/invoices-pays', 'INVPAY', '2021-08-03 16:22:38', 29, null, null, null),
('MCO', 'Очередь заданий', null, null, '/mfrs/jobs-queue', 'MCO', '2023-02-15 17:15:17', 106, null, null, null),
('MFC', 'Детали сборки', null, null, '/mfrs/plans/0/items', 'MFC', '2023-02-15 17:15:17', 104, null, 'SDOCS_MFR_ITEMS', 'CONTENT_ID'),
('MFD', 'Тех.выписки', null, null, '/mfrs/plans/0/drafts', 'MFD', null, 9, null, 'MFR_DRAFTS', 'DRAFT_ID'),
('MFE', 'Оборудование', null, null, '/mfrs/equipments', 'MFE', null, 10, null, null, null),
('MFJ', 'Производственные задания', null, null, '/mfrs/jobs', 'MFJ', '2023-02-15 17:15:17', 105, null, 'MFR_PLANS_JOBS', 'PLAN_JOB_ID'),
('MFL', 'Производственные участки', null, null, '/mfrs/places', 'MFL', null, 12, null, null, null),
('MFM', 'Материалы', null, null, '/mfrs/plans/0/materials', 'MFM', '2021-08-11 13:56:43', 33, null, 'SDOCS_MFR_MATERIALS', 'CONTENT_ID'),
('MFO', 'Операции деталей', null, null, '/mfrs/plans/0/opers', 'MFO', null, 13, null, null, null),
('MFP', 'Производственные планы', null, null, '/mfrs/plans', 'MFP', '2023-02-15 17:15:17', 103, null, 'MFR_PLANS', 'PLAN_ID'),
('MFR', 'Производственные заказы', null, null, '/mfrs/docs', 'MFR', '2023-02-15 17:15:17', 102, null, 'MFR_SDOCS', 'DOC_ID'),
('MFTRF', 'Передаточные накладные', null, null, '/mfrs/doctrfs', 'MFTRF', '2023-02-15 17:15:17', 107, 1, 'V_MFR_SDOCS_TRF', 'DOC_ID'),
('MFW', 'Табели рабочего времени', null, null, '/mfrs/wksheets', 'MFW', '2024-07-10 11:04:27', 133, null, null, null),
('MFWD', 'Сменные задания', null, null, '/mfrs/wksheets/details', 'MFWD', '2024-07-11 19:42:22', 157, null, null, null),
('MFWJ', 'Табели (задания)', null, null, '/mfrs/wksheets/jobs', 'MFWJ', '2024-07-11 00:08:47', 146, null, null, null),
('MOL', 'Сотрудники', null, null, '/mols', 'MOL', '2024-02-10 00:09:06', 130, null, 'MOLS', 'MOL_ID'),
('P', 'Товарные позиции', null, null, '/products', 'PRODUCT', null, 17, null, 'PRODUCTS', 'PRODUCT_ID'),
('PLP', 'Планы ПДС', null, null, '/planpays', 'PLANPAY', null, 18, null, 'PLAN_PAYS', 'PLAN_PAY_ID'),
('PO', 'Заявки на оплату', null, null, '/finance/payorders', 'PAYORDER', null, 19, null, 'PAYORDERS', 'PAYORDER_ID'),
('PRJ', 'Проекты', 'Проекты из журнала', 'select project_id as ID,  NAME from projects where name like ''%'' + {0} + ''%'' or {0} is null', '/projects', 'PROJECT', null, 20, null, 'PROJECTS', 'PROJECT_ID'),
('PRR', 'Результаты проекта', null, null, null, null, null, 21, null, null, null),
('PTF', 'Портфель проектов', null, null, '/projects/portfolio', null, null, 22, null, null, null),
('PTR', 'Риски проекта', null, null, null, null, null, 23, null, null, null),
('PTS', 'Задачи проекта', 'Задачи из плана проекта', null, null, null, null, 24, null, null, null),
('SBJ', 'Субъекты', 'Субъекты компании,  по которым учитываются движения', 'select subject_id as ID,  NAME from subjects where pred_id is not null and (name like ''%'' + {0} + ''%'' or {0} is null) order by name', null, null, null, 25, null, null, null),
('SD', 'Товарные документы|Счета', null, null, '/sdocs', 'SDOC', null, 26, 1, 'SDOCS', 'DOC_ID'),
('SWP', 'Замены материалов', null, null, '/mfrs/swaps', 'SWAP', null, 27, null, null, null),
('TSK', 'Задачи', 'Задачи журнала задач', null, '/tasks', 'TASK', null, 28, null, 'TASKS', 'TASK_ID')
;SET IDENTITY_INSERT OBJS_TYPES OFF;
GO

-- SEED: OPTIONS_LISTS
;SET IDENTITY_INSERT OPTIONS_LISTS ON;
IF NOT EXISTS(SELECT 1 FROM OPTIONS_LISTS)
INSERT INTO OPTIONS_LISTS(L_GROUP, ID, NAME, NOTE, ROW_ID, SHORT_NAME) VALUES
('DealMarketing', 'DealMark1', 'Кон. потр.', null, 4, null),
('DealMarketing', 'DealMark3', 'Партнер', null, 5, null),
('DealMarketing', 'DealMark4', 'KIK', null, 6, null),
('DealMarketing', 'DealMark6', 'Закуп.центр', null, 7, null),
('DealMarketing', 'DealMark7', 'Ген.подрядчик', null, 8, null),
('DealMarketing', 'DealMark8', 'Инжиниринг', null, 9, null),
('DealMarketing', 'DealMark9', 'Проектный инст.', null, 10, null),
('DealMarketing', 'DM1', '-', null, 11, null),
('DealMarketing', 'DM2', 'Генеральный подрядчик', null, 12, null),
('DealMarketing', 'DM3', 'Дилер', null, 13, null),
('DealMarketing', 'DM4', 'Инжиниринговая компания', null, 14, null),
('DealMarketing', 'DM5', 'Коммерческий партнер', null, 15, null),
('DealMarketing', 'DM6', 'Конечный потребитель', null, 16, null),
('DealMarketing', 'DM7', 'П1К', null, 17, null),
('DealMarketing', 'DM8', 'Посредник', null, 18, null),
('DealMarketing', 'DM9', 'Ремонтная организация', null, 19, null),
('DealStates', 'State1', 'Подписана Спецификация', null, 20, null),
('DealStates', 'State2', 'Запуск в производство', null, 21, null),
('DealStates', 'State3', 'Начало производства', null, 22, null),
('DealStates', 'State4', 'Выпуск из производства', null, 23, null),
('DealStates', 'State5', 'Отгружено', null, 24, null),
('DealStates', 'State6', 'Доставлено', null, 25, null),
('DeliveryBases', 'CFR', 'CFR', 'Основная перевозка оплачена. Товар доставляется до порта Покупатель.', 26, null),
('DeliveryBases', 'CIF', 'CIF', 'Оплачена страховка и перевозка Товара до порта Покупатель.', 27, null),
('DeliveryBases', 'CIP', 'CIP', 'Оплачена страховка и перевозка Товара до места нахождения перевозчика Покупателя. Риски и расходы по разгрузке,  а также расходы по страхованию Товара на оставшемся пути несет Покупатель.', 28, null),
('DeliveryBases', 'CPT', 'CPT', 'Оплачена перевозка Товара до места нахождения перевозчика Покупателя. Риски и расходы по разгрузке Товара несет Покупатель.', 29, null),
('DeliveryBases', 'DAP', 'DAP', 'Оплачена доставка до места назначения Покупателя. Риски и расходы по разгрузке Товара несет Покупатель.', 30, null),
('DeliveryBases', 'DAT', 'DAT', 'Оплачена доставка до терминала Покупателя. Риски и расходы по разгрузке Товара несет Поставщик.', 31, null),
('DeliveryBases', 'DDP', 'DDP', 'Оплачена доставка и все таможенные пошлины до места назначения Покупателя. Риски и расходы по разгрузке Товара несет Покупатель.', 32, null),
('DeliveryBases', 'EXW', 'EXW', 'Товар забирается со склада Поставщика. Расходы и риски по погрузке и перевозке Товара несет Покупатель.', 33, null),
('DeliveryBases', 'FAS', 'FAS', 'Основная перевозка не оплачена. Товар доставляется к кораблю Покупателя до борта судна.', 34, null),
('DeliveryBases', 'FCA', 'FCA', 'Основная перевозка не оплачена. Товар отгружается перевозчику Покупателя. Риски и расходы по отгрузке товара несет Поставщик.', 35, null),
('DeliveryBases', 'FOB', 'FOB', 'Основная перевозка не оплачена. Товар погружается на корабль Покупателя. Риски и расходы по погрузке Товара на борт корабля несет Поставщик.', 36, null),
('DeliveryFrom', 'DF1', 'С мом. пост. аванса', 'с момента поступления аванса на расчётный счёт Поставщика с правом досрочной поставки.', 37, null),
('DeliveryFrom', 'DF2', 'С мом. подп. специфик.', 'с момента подписания Спецификаци', 38, null),
('NdsRatios', '0.00', '0%', null, 59, null),
('NdsRatios', '0.18', '18%', null, 60, null),
('NdsRatios', '0.20', '20%', null, 61, null),
('PlanPaysStatuses', '0', 'Черновик', null, 62, null),
('PlanPaysStatuses', '1', 'Отправлен', null, 63, null),
('PlanPaysStatuses', '-1', 'Удалён', null, 64, null),
('PlanPaysStatuses', '10', 'Принят', null, 65, null),
('PlanPaysStatuses', '20', 'Закрыт', null, 66, null),
('MfrPlanStatuses', '0', 'Черновик', null, 147, null),
('MfrPlanStatuses', '1', 'Открыт', null, 148, null),
('MfrPlanStatuses', '100', 'Закрыт', null, 150, null),
('MfrSdocsSources', '1', 'КИСП', null, 257, null),
('MfrSdocsSources', '2', 'ИМПОРТ', null, 258, null),
('SdocType8Milestones', '1', 'Подписана спецификация', null, 266, null),
('SdocType8Milestones', '2', 'Уведомление о готовности', null, 267, null),
('SdocType8Milestones', '3', 'Поступило на склад', null, 268, null),
('SdocType8Milestones', '4', 'Выдано в производство', null, 269, null),
('SdocType1Milestones', '1', 'Запуск', null, 308, 'З'),
('SdocType1Milestones', '2', 'Подписание спецификации', null, 309, 'А'),
('SdocType1Milestones', '3', 'Изготовление', null, 310, 'И'),
('SdocType1Milestones', '4', 'Уведомление о готовности', null, 311, 'УГ'),
('SdocType1Milestones', '5', 'Отгрузка', null, 312, 'О'),
('SdocType1Milestones', '6', 'Доставка', null, 313, 'Д'),
('SdocType1Milestones', '7', 'Пусконаладка', null, 314, 'П'),
('SdocType1Milestones', '8', 'Акт выполненых работ', null, 315, 'АКТ'),
('MfrPlanJobStatuses', '-100', 'Архив', null, 436, null),
('MfrPlanJobStatuses', '-2', 'Отменено', null, 437, null),
('MfrPlanJobStatuses', '-1', 'Удалено', null, 438, null),
('MfrPlanJobStatuses', '0', 'Черновик', null, 439, null),
('MfrPlanJobStatuses', '1', 'Отправлено', null, 440, null),
('MfrPlanJobStatuses', '2', 'Исполнение', null, 441, null),
('MfrPlanJobStatuses', '10', 'Исполнено', null, 442, null),
('MfrPlanJobStatuses', '100', 'Закрыто', null, 443, null),
('PayorderPaths', '1', 'МС', null, 532, null),
('PayorderPaths', '2', 'МС > Русэлпром', null, 533, null),
('PayorderPaths', '3', 'МС > Русэлпром > Ресурс', null, 534, null),
('PayorderPaths', '4', 'МС > Русэлпром > Русэлпром-ЛЭЗ', null, 535, null),
('PayorderPaths', '5', 'МС > Русэлпром > РуЭМ', null, 536, null),
('PayorderPaths', '6', 'МС > Русэлпром > Техснаб', null, 537, null),
('PayorderPaths', '7', 'Ресурс', null, 538, null),
('PayorderPaths', '8', 'Русэлпром', null, 539, null),
('PayorderPaths', '9', 'Русэлпром > ВЭМЗ', null, 540, null),
('PayorderPaths', '10', 'Русэлпром > МС', null, 541, null),
('PayorderPaths', '11', 'Русэлпром > НИПТИЭМ', null, 542, null),
('PayorderPaths', '12', 'Русэлпром > НПО ЛЭЗ', null, 543, null),
('PayorderPaths', '13', 'Русэлпром > Ресурс', null, 544, null),
('PayorderPaths', '14', 'Русэлпром > Русэлпром-ЛЭЗ', null, 545, null),
('PayorderPaths', '15', 'Русэлпром > РуЭМ', null, 546, null),
('PayorderPaths', '16', 'Русэлпром > СЭЗ', null, 547, null),
('PayorderPaths', '17', 'Русэлпром > ТД', null, 548, null),
('PayorderPaths', '18', 'Русэлпром > Техснаб', null, 549, null),
('PayorderPaths', '19', 'Русэлпром > ЭМ', null, 550, null),
('PayorderPaths', '20', 'ТД', null, 551, null),
('PayorderPaths', '21', 'ТД > МС', null, 552, null),
('PayorderPaths', '22', 'ТД > МС > Русэлпром', null, 553, null),
('PayorderPaths', '23', 'ТД > МС > Русэлпром > Техснаб', null, 554, null),
('PayorderPaths', '24', 'ТД > Русэлпром', null, 555, null),
('PayorderPaths', '25', 'ТД > Русэлпром > НПО ЛЭЗ', null, 556, null),
('PayorderPaths', '26', 'ТД > Русэлпром > Ресурс', null, 557, null),
('PayorderPaths', '27', 'ТД > Русэлпром > Русэлпром-ЛЭЗ', null, 558, null),
('PayorderPaths', '28', 'ТД > Русэлпром > РуЭМ', null, 559, null),
('PayorderPaths', '29', 'ТД > Русэлпром > Техснаб', null, 560, null),
('PayorderPaths', '30', 'Техснаб', null, 561, null),
('PayorderPaths', '31', 'ЭМ', null, 562, null),
('PayorderPaths', '32', 'ЭМ > Русэлпром', null, 563, null),
('PayorderPaths', '33', 'ЭМ > Русэлпром > ВЭМЗ', null, 564, null),
('PayorderPaths', '34', 'ЭМ > Русэлпром > НИПТИЭМ', null, 565, null),
('PayorderPaths', '35', 'ЭМ > Русэлпром > НПО ЛЭЗ', null, 566, null),
('PayorderPaths', '36', 'ЭМ > Русэлпром > Ресурс', null, 567, null),
('PayorderPaths', '37', 'ЭМ > Русэлпром > Русэлпром-ЛЭЗ', null, 568, null),
('PayorderPaths', '38', 'ЭМ > Русэлпром > РуЭМ', null, 569, null),
('PayorderPaths', '39', 'ЭМ > Русэлпром > СЭЗ', null, 570, null),
('PayorderPaths', '40', 'ЭМ > Русэлпром > Техснаб', null, 571, null),
('PayorderPaths', '41', 'ЭМ > РуЭМ > Техснаб', null, 572, null),
('PayorderPaths', '42', 'Менеджмент', null, 573, null),
('PayorderPaths', '43', 'Менеджмент > Техснаб', null, 574, null),
('PayorderPaths', '44', 'Менеджмент > Русэлпром-ЛЭЗ', null, 575, null),
('MfrItemStatuses', '-1', 'Удалено', null, 723, null),
('MfrItemStatuses', '0', 'Черновик', null, 724, null),
('MfrItemStatuses', '3', 'Запрет', null, 725, null),
('MfrItemStatuses', '2', 'Готов к выдаче', null, 726, null),
('MfrItemStatuses', '1', 'В работе', null, 727, null),
('MfrItemStatuses', '100', 'Сделано', null, 728, null),
('MfrItemStatuses', '200', 'Проверка', null, 729, null)
;SET IDENTITY_INSERT OPTIONS_LISTS OFF;

DELETE FROM OPTIONS_LISTS where L_GROUP = 'MfrWkSheetsStatuses'
INSERT INTO OPTIONS_LISTS(L_GROUP,  ID,  NAME) VALUES 
('MfrWkSheetsStatuses',  -2,  'Отменено'),
('MfrWkSheetsStatuses',  -1,  'Удалено'),
('MfrWkSheetsStatuses',  0,  'Черновик'),
('MfrWkSheetsStatuses',  1,  'Выдан'),
('MfrWkSheetsStatuses',  2,  'Исполнение'),
('MfrWkSheetsStatuses',  100,  'Закрыто')

DELETE FROM OPTIONS_LISTS where L_GROUP = 'SupplyPaysMilestones'
INSERT INTO OPTIONS_LISTS(L_GROUP,  ID,  NAME) VALUES 
('SupplyPaysMilestones',  1,  'Подписана спецификация'),
('SupplyPaysMilestones',  2,  'Уведомление о готовности'),
('SupplyPaysMilestones',  3,  'Поступление на склад'),
('SupplyPaysMilestones',  4,  'ЛЗК'),
('SupplyPaysMilestones',  5,  '#5'),
('SupplyPaysMilestones',  6,  '#6')

GO

-- SEED: OPTIONS
;SET IDENTITY_INSERT OPTIONS ON;
IF NOT EXISTS(SELECT 1 FROM OPTIONS)
INSERT INTO OPTIONS(O_GROUP, O_PARENT, O_KEY, O_NAME, O_TYPE, O_TYPE_PARAM, O_REQUIRED, O_READONLY, O_DEFAULT, O_FLEX, O_CSS, O_HINT, O_TOOLTIP, ID) VALUES
('PROJECT', '', 'PROJECT_CONTRACT', 'Контракт', '', '', null, null, null, '', '', '', '', 1134),
('PROJECT', 'PROJECT_CONTRACT', 'ID', 'ID', 'string', '', null, 1, null, '', 'hidden', '', '', 1135),
('PROJECT', 'PROJECT_CONTRACT', 'SUBJECT_ID', 'Контрактодержатель', 'list', 'subjects0', null, null, null, '273px', '', '', '', 1136),
('PROJECT', 'PROJECT_CONTRACT', 'VENDOR_ID', 'Производитель', 'list', 'vendors', null, null, null, '273px', 'spacer', '', '', 1137),
('PROJECT', 'PROJECT_CONTRACT', 'DOGOVOR_NUMBER', '№ договора', 'string', '', null, null, null, '150px', 'm-2', '', '', 1138),
('PROJECT', 'PROJECT_CONTRACT', 'DOGOVOR_DATE', 'Дата поставки', 'date', '', null, null, null, '', '', '', '', 1139),
('PROJECT', 'PROJECT_CONTRACT', 'SPEC_NUMBER', '№ спецификации', 'string', '', null, null, null, '150px', '', '', '', 1140),
('PROJECT', 'PROJECT_CONTRACT', 'SPEC_DATE', 'Дата спецификации', 'date', '', null, null, null, '', 'spacer', '', '', 1141),
('PROJECT', 'PROJECT_CONTRACT', 'CCY_ID', 'Валюта расчетов', 'olist', 'Ccy', null, null, null, '100px', 'm-2', '', '', 1142),
('PROJECT', 'PROJECT_CONTRACT', 'VALUE_CCY', 'Сумма контракта', 'number', '', null, null, null, '160px', 'text-right spacer', '', '', 1143),
('PROJECT', 'PROJECT_CONTRACT', 'PRINCIPAL', 'Договор с Принципалом', 'autocomplete', '{"url": "/finance/api/deal/principalsDogovors"}', null, null, null, '273px', 'm-2', '', '', 1144),
('PROJECT', 'PROJECT_CONTRACT', 'PRINCIPAL_COMMISSION', 'Договор Комиссии', 'autocomplete', '{"url": "/finance/api/deal/principalsCommissions"}', null, null, null, '273px', '', '', '', 1145),
('PROJECT', 'PROJECT_CONTRACT', 'PRINCIPAL_SPEC', 'Спецификация', 'autocomplete', '{"url": "/finance/api/deal/principalsSpecs"}', null, null, null, '273px', 'spacer', '', '', 1146),
('PROJECT', 'PROJECT_CONTRACT', 'CUSTOMER', 'Покупатель/Заказчик', 'autocomplete', 'agents', null, null, null, '372px', 'm-2', '', '', 1147),
('PRODUCT', '', 'F1', 'Параметры', '', '', null, null, null, '', '', '', '', 1204),
('PRODUCT', 'F1', 'GROUP1', 'Grp', 'product-groups1', '', null, null, null, '200px', 'option-control', '', '', 1205),
('PRODUCT', 'F1', 'GROUP2', 'GrpPL', 'product-groups2', '', null, null, null, '370px', 'option-control', '', '', 1206),
('PRODUCT', 'F1', 'ENGINE_SPEED', 'Частота вращения,  об/мин', 'product-olist', 'ENGINE_SPEED', null, null, null, '200px', 'option-control', '', '', 1207),
('PRODUCT', 'F1', 'MOTOR_POWER', 'Мощность,  кВт', 'product-olist', 'MOTOR_POWER', null, null, null, '200px', 'option-control', '', '', 1208),
('PRODUCT', 'F1', 'MOTOR_SIZE', 'Размер', 'product-olist', 'MOTOR_SIZE', null, null, null, '200px', 'option-control', '', '', 1209),
('PRODUCT', 'F1', 'MOTOR_LINE', 'Line', 'product-olist', 'MOTOR_LINE', null, null, null, '200px', 'option-control', '', '', 1210),
('PRODUCT', 'F1', 'MOTOR_SERIES', 'Серия', 'product-olist', 'MOTOR_SERIES', null, null, null, '200px', 'option-control', '', '', 1211),
('PRODUCT', 'F1', 'MOTOR_ENERGY', 'Энерго эфф-ть', 'product-olist', 'MOTOR_ENERGY', null, null, null, '200px', 'option-control', '', '', 1212),
('PRODUCT', 'F1', 'MOTOR_VOLTAGE', 'Напряжение,  В', 'product-olist', 'MOTOR_VOLTAGE', null, null, null, '200px', 'option-control', '', '', 1213),
('MFR_ROUTE', '', 'F1', 'Общие', '', '', null, null, null, '', '', '', '', 1274),
('MFR_ROUTE', 'F1', 'SUBJECT_ID', 'Субъект', 'list', 'subjects', null, null, null, '273px', 'spacer', '', '', 1275),
('MFR_ROUTE', 'F1', 'NAME', 'Название', 'string', '', null, null, null, '', 'w-50', '', '', 1276),
('MFR_ROUTE', 'F1', 'NOTE', 'Примечание', 'string', '', null, null, null, '', 'w-100', '', '', 1277),
('MFR_ROUTE', '', 'F2', 'Состав операций', '', '', null, null, null, '', '', '', '', 1278),
('MFR_ROUTE', 'F2', 'DETAILs', 'Состав операций', 'route-rows', '', null, null, null, '', 'w-100', '', '', 1279),
('MFR_EQUIPMENT', '', 'F1', 'Общие', '', '', null, null, null, '', '', '', '', 1280),
('MFR_EQUIPMENT', 'F1', 'SUBJECT_ID', 'Субъект', 'list', 'subjects0', null, null, null, '273px', 'spacer', '', '', 1281),
('MFR_EQUIPMENT', 'F1', 'STATUS_ID', 'Статус', 'list', '/mfrs/api/MfrEquipments/statuses', null, null, null, '', '', '', '', 1282),
('MFR_EQUIPMENT', 'F1', 'NUMBER', '№документа', 'string', '', null, null, null, '', '', '', '', 1283),
('MFR_EQUIPMENT', 'F1', 'D_DOC', 'Дата регистрации', 'date', '', null, null, null, '', '', 'Дата регистрации', '', 1284),
('MFR_EQUIPMENT', 'F1', 'D_RELEASE', 'Дата выпуска', 'date', '', null, null, null, '', 'spacer', 'Дата выпуска', '', 1285),
('MFR_EQUIPMENT', 'F1', 'NAME', 'Наименование', 'string', '', null, null, null, '', 'w-100', '', '', 1286),
('MFR_EQUIPMENT', 'F1', 'MODEL', 'Модель', 'string', '', null, null, null, '', '', '', '', 1287),
('MFR_EQUIPMENT', 'F1', 'PROP_POWER', 'Мощность,  кВт', 'string', '', null, null, null, '', '', '', '', 1288),
('MFR_EQUIPMENT', 'F1', 'PRICE_HOUR', 'Стоимость машино-часа', 'number', '', null, null, null, '', '', '', '', 1289),
('MFR_EQUIPMENT', 'F1', 'BALANCE_VALUE', 'Учётная стоимость', 'number', '', null, null, null, '', '', '', '', 1290),
('MFR_EQUIPMENT', 'F1', 'MONTH_LOADING', 'Фонд рабочего времени в месяц', 'number', '', null, null, null, '', '', '', '', 1291),
('MFR_EQUIPMENT', 'F1', 'RESOURCE', 'Связь с ресурсом', 'autocomplete', '{"url": "/api/projects/resources"}', null, null, null, '375px', '', '', '', 1292),
('MFR_EQUIPMENT', 'F1', 'SPECIFICATION', 'Спецификация', 'string', '', null, null, null, '', 'w-100', '', '', 1293),
('MFR_EQUIPMENT', 'F1', 'NOTE', 'Примечание', 'string', '', null, null, null, '', 'w-100', '', '', 1294),
('BUYORDER', '', 'F1', 'Общие', '', '', null, null, null, '', '', '', '', 1329),
('BUYORDER', 'F1', 'SUBJECT_ID', 'Контрактодержатель', 'list', 'subjects', null, null, null, '273px', '', '', '', 1330),
('BUYORDER', 'F1', 'STATUS_ID', 'Статус', 'list', '/finance/api/invoice/statuses', null, null, null, '140px', 'mb-3 spacer', '', '', 1331),
('BUYORDER', 'F1', 'D_DOC', 'Дата', 'date', '', null, null, null, '', '', '', '', 1332),
('BUYORDER', 'F1', 'NUMBER', '№ документа', 'string', '', null, null, null, '', '', '', '', 1333),
('BUYORDER', 'F1', 'AGENT', 'Контрагент', 'autocomplete', 'agents', null, null, null, '415px', 'spacer', '', '', 1334),
('BUYORDER', 'F1', 'DOGOVOR_NUMBER', '№ договора поставки', 'string', '', null, null, null, '150px', '', 'Договор поставки №', '', 1335),
('BUYORDER', 'F1', 'DOGOVOR_DATE', 'Дата договора поставки', 'date', '', null, null, null, '', '', '', '', 1336),
('BUYORDER', 'F1', 'SPEC_NUMBER', '№ спецификации', 'string', '', null, null, null, '150px', '', 'Спецификация №', '', 1337),
('BUYORDER', 'F1', 'SPEC_DATE', 'Дата спецификации', 'date', '', null, null, null, '', '', '', '', 1338),
('BUYORDER', 'F1', 'D_DELIVERY', 'Срок поставки', 'date', '', null, null, null, '', 'mb-3 spacer', 'Срок поставки', '', 1339),
('BUYORDER', 'F1', 'CCY_ID', 'Валюта', 'olist', 'ccy', null, null, null, '100px', '', '', '', 1340),
('BUYORDER', 'F1', 'VALUE_CCY', 'Сумма', 'number', '', null, 1, null, '150px', 'text-right', '', '', 1341),
('BUYORDER', 'F1', 'MOL', 'Ответственный', 'autocomplete', 'mols', null, null, null, '215px', 'spacer', '', '', 1342),
('BUYORDER', 'F1', 'NOTE', 'Примечание', 'string', '', null, null, null, '', 'w-100', '', '', 1343),
('BUYORDER', '', 'F2', 'Товарный состав', '', '', null, null, null, '', '', '', '', 1344),
('BUYORDER', 'F2', 'PRODUCTs', '', 'buyorder-products', '', null, null, null, '', 'w-100', '', '', 1345),
('BUYORDER', '', 'F3', 'График оплат', '', '', null, null, null, '', '', '', '', 1346),
('BUYORDER', 'F3', 'MILESTONEs', '', 'buyorder-milestones', '', null, null, null, '', 'w-100', '', '', 1347),
('BUYORDER', '', 'F4', 'Согласование', '', '', null, null, null, '', '', '', '', 1348),
('BUYORDER', 'F4', 'REFKEY', 'Состав операций', 'tasks', '', null, null, null, '', 'w-100', '', '', 1349)
;SET IDENTITY_INSERT OPTIONS OFF;
GO

-- SEED: PAYORDERS_STATUSES
IF NOT EXISTS(SELECT 1 FROM PAYORDERS_STATUSES)
INSERT INTO PAYORDERS_STATUSES(STATUS_ID, NAME, IS_DELETED) VALUES
(-2, 'Архив', 0),
(-1, 'Удалено', 0),
(0, 'Черновик', 0),
(1, 'Отправлено', 0),
(2, 'Согласование', 0),
(3, 'Согласовано', 0),
(4, 'К оплате', 0),
(5, 'Частичная олата', 0),
(10, 'Оплачено', 0)
GO

-- SEED: PAYORDERS_TYPES
IF NOT EXISTS(SELECT 1 FROM PAYORDERS_TYPES)
INSERT INTO PAYORDERS_TYPES(TYPE_ID, NAME) VALUES
(1, 'Заявка на оплату'),
(2, 'Фин.Выдача'),
(3, 'Фин.Погашение'),
(4, 'Заявка на материалы')
GO

-- SEED: PERIODICITY
IF NOT EXISTS(SELECT 1 FROM PERIODICITY)
INSERT INTO PERIODICITY(PERIODICITY_ID, NAME) VALUES
(1, 'Неделя'),
(2, 'Месяц'),
(3, 'Квартал'),
(4, 'Полугодие'),
(5, 'Год')
GO

-- SEED: PLAN_PAYS_STATUSES
IF NOT EXISTS(SELECT 1 FROM PLAN_PAYS_STATUSES)
INSERT INTO PLAN_PAYS_STATUSES(STATUS_ID, NAME) VALUES
(-1, 'Удалён'),
(0, 'Черновик'),
(1, 'Отправлен'),
(10, 'Принят'),
(20, 'Закрыт')
GO

-- SEED: PLAN_PAYS_TYPES
IF NOT EXISTS(SELECT 1 FROM PLAN_PAYS_TYPES)
INSERT INTO PLAN_PAYS_TYPES(PAY_TYPE_ID, NAME) VALUES
(1, 'Аванс'),
(2, 'Расчёт'),
(3, 'Деб.тек.'),
(4, 'Деб.прос.'),
(5, 'Промежуточный расчёт'),
(6, 'Оплата по готовности')
GO

-- SEED: PLISTS_STATUSES
IF NOT EXISTS(SELECT 1 FROM PLISTS_STATUSES)
INSERT INTO PLISTS_STATUSES(STATUS_ID, NAME, IS_DELETED) VALUES
(-1, 'Удалено', 0),
(0, 'Черновик', 0),
(1, 'Отравлен', 0),
(5, 'Принят', 0),
(10, 'Архив', 0)
GO

-- SEED: PRODUCTS_STATUSES
IF NOT EXISTS(SELECT 1 FROM PRODUCTS_STATUSES)
INSERT INTO PRODUCTS_STATUSES(STATUS_ID, NAME, IS_DELETED) VALUES
(-1, 'Удалено', 0),
(0, 'Черновик', 0),
(1, 'Отправлен', 0),
(5, 'Принят', 0),
(10, 'Архив', 0)
GO

-- SEED: PRODUCTS_TYPES
IF NOT EXISTS(SELECT 1 FROM PRODUCTS_TYPES)
INSERT INTO PRODUCTS_TYPES(TYPE_ID, NAME) VALUES
(0, '-'),
(1, 'Материалы'),
(2, 'Детали'),
(3, 'Сборочные единицы'),
(4, 'Агрегаты'),
(5, 'Стандартные изделия'),
(6, 'Прочие изделия (компоненты)'),
(7, 'Электрическая машина')
GO

-- SEED: PROJECTS_DURATIONS
IF NOT EXISTS(SELECT 1 FROM PROJECTS_DURATIONS)
INSERT INTO PROJECTS_DURATIONS(DURATION_ID, NAME, FACTOR, FACTOR24) VALUES
(1, 'мин', 0.00208333, 0.000694444),
(2, 'ч', 0.125, 0.0416667),
(3, 'дн', 1, 1)
GO

-- SEED: PROJECTS_GROUPS
;SET IDENTITY_INSERT PROJECTS_GROUPS ON;
IF NOT EXISTS(SELECT 1 FROM PROJECTS_GROUPS)
INSERT INTO PROJECTS_GROUPS(GROUP_ID, NAME, DESCRIPTION, ADD_DATE, IS_SYSTEM) VALUES
(0, '<не определена>', null, '2016-05-11 13:58:35', 1),
(1, 'ПРОИЗВОДСТВО', null, '2016-05-11 13:58:35', 0),
(2, 'КОНТРАКТЫ', null, '2016-05-11 13:58:35', 0),
(3, 'СТРОИТЕЛЬСТВО', null, '2016-05-11 13:58:35', 0),
(4, 'РАЗВИТИЕ', null, '2016-05-11 13:58:35', 0),
(5, 'Производственные заказы', null, '2020-01-25 23:23:00', 1),
(10, 'Текущая деятельность', null, '2020-03-03 11:58:13', 0),
(100, 'Шаблон', null, '2019-02-01 19:06:00', 0)
;SET IDENTITY_INSERT PROJECTS_GROUPS OFF;
GO

-- SEED: PROJECTS_PRIORITIES
IF NOT EXISTS(SELECT 1 FROM PROJECTS_PRIORITIES)
INSERT INTO PROJECTS_PRIORITIES(PRIORITY_ID, NAME, CSS_CLASS) VALUES
(-1, 'Ошибка', 'prior prior--1'),
(0, 'Обычный', 'prior prior-0'),
(1, 'Выделенный', 'prior prior-1'),
(2, 'Важный', 'prior prior-2'),
(3, 'Критичный', 'prior prior-3')
GO

-- SEED: PROJECTS_REPS_STATUSES
IF NOT EXISTS(SELECT 1 FROM PROJECTS_REPS_STATUSES)
INSERT INTO PROJECTS_REPS_STATUSES(STATUS_ID, NAME) VALUES
(-1, 'Удалено'),
(0, 'Черновик'),
(1, 'Исполнение'),
(2, 'Анализ'),
(3, 'Возвращено из архива'),
(10, 'Архив')
GO

-- SEED: PROJECTS_REPS_TYPES
IF NOT EXISTS(SELECT 1 FROM PROJECTS_REPS_TYPES)
INSERT INTO PROJECTS_REPS_TYPES(REP_TYPE_ID, NAME) VALUES
(1, 'Неделя'),
(2, 'Месяц'),
(3, 'Вручную')
GO

-- SEED: PROJECTS_RESOURCES_AGGREGATIONS
IF NOT EXISTS(SELECT 1 FROM PROJECTS_RESOURCES_AGGREGATIONS)
INSERT INTO PROJECTS_RESOURCES_AGGREGATIONS(AGGREGATION_ID, NAME, DESCRIPTION) VALUES
(1, 'Складируемый', 'Ресурсы типа "энергия": ресурс вырабатывается,  накапливается,  потребляется.'),
(2, 'Нескладируемый', 'Ресурс типа "мощность": ресурс или предоставляется или расходуется.')
GO

-- SEED: PROJECTS_RESOURCES_DISTRIBUTIONS
IF NOT EXISTS(SELECT 1 FROM PROJECTS_RESOURCES_DISTRIBUTIONS)
INSERT INTO PROJECTS_RESOURCES_DISTRIBUTIONS(DISTRIBUTION_ID, NAME, DESCRIPTION) VALUES
(1, 'Равномерно', 'Ресурс распределяется равномерно по дням от начала до завершения задачи'),
(2, 'В начале', 'Ресурс расходуется/используется на дату начала задачи'),
(3, 'В конце', 'Ресурс расходуется/используется на дату завершения задачи')
GO

-- SEED: PROJECTS_RESOURCES_TYPES
IF NOT EXISTS(SELECT 1 FROM PROJECTS_RESOURCES_TYPES)
INSERT INTO PROJECTS_RESOURCES_TYPES(TYPE_ID, NAME, NOTE) VALUES
(1, 'Труд', null),
(2, 'Оборудование', null),
(3, 'Кооперация', null)
GO

-- SEED: PROJECTS_RESULTS_CATEGORIES
IF NOT EXISTS(SELECT 1 FROM PROJECTS_RESULTS_CATEGORIES)
INSERT INTO PROJECTS_RESULTS_CATEGORIES(CATEGORY_ID, NAME) VALUES
(1, 'Событие'),
(2, 'Опыт'),
(3, 'Достижение')
GO

-- SEED: PROJECTS_RISKS_ACTIONS
;SET IDENTITY_INSERT PROJECTS_RISKS_ACTIONS ON;
IF NOT EXISTS(SELECT 1 FROM PROJECTS_RISKS_ACTIONS)
INSERT INTO PROJECTS_RISKS_ACTIONS(RISK_ID, ACTION_ID, NAME, ACTIONS, D_RESPONSE, IS_DELETED, ADD_DATE) VALUES
(5, 1, 'Получение билда', 'тщательнейшее тестирование', '1', 0, '2018-10-04 16:22:32')
;SET IDENTITY_INSERT PROJECTS_RISKS_ACTIONS OFF;
GO

-- SEED: PROJECTS_RISKS_CATEGORIES
IF NOT EXISTS(SELECT 1 FROM PROJECTS_RISKS_CATEGORIES)
INSERT INTO PROJECTS_RISKS_CATEGORIES(CATEGORY_ID, NAME) VALUES
(1, 'Технический'),
(2, 'Внешний'),
(3, 'Организационный'),
(4, 'Управленческий')
GO

-- SEED: PROJECTS_RISKS_STATUSES
IF NOT EXISTS(SELECT 1 FROM PROJECTS_RISKS_STATUSES)
INSERT INTO PROJECTS_RISKS_STATUSES(STATUS_ID, NAME) VALUES
(0, 'Черновик'),
(1, 'Текущий'),
(2, 'Просрочен'),
(10, 'Архив')
GO

-- SEED: PROJECTS_SECTIONS
IF NOT EXISTS(SELECT 1 FROM PROJECTS_SECTIONS)
INSERT INTO PROJECTS_SECTIONS(SECTION_ID, NAME, HREF, CSS, IS_DEFAULT, IS_REQUIRED, IKEY, SORT_ID, DIVIDER_AFTER, CSS_LI, IS_PROGRAM, IS_DEAL) VALUES
(1, 'Общие', '/projects/{id}/card', 'fa fa-table', 1, 1, 'view', 1, null, null, 1, 1),
(2, 'Команда', '/projects/{id}/mols', 'fa fa-users', 1, 0, 'mols', 2, 1, null, 1, 1),
(3, 'Обязательства', '/projects/{id}/duty', 'fa fa-flag text-error', 0, 0, 'duty', 3, null, null, null, null),
(4, 'Работы', '/projects/{id}/plan', 'fa fa-indent', 1, 0, 'plan', 4, null, null, 1, 1),
(5, 'Планы', '/projects/{id}/reps', 'fa fa-flag', 0, 0, 'reps', 5, null, null, 1, null),
(6, 'Гант', '/projects/{id}/gantt', 'fa fa-calendar', 1, 0, 'gantt', 6, null, null, 1, null),
(7, 'Бюджеты', '/projects/{id}/budgets', 'fa fa-rub', 0, 0, 'budgets', 8, null, null, 1, null),
(8, 'Закупки', '/projects/{id}/buy', 'fa fa-rub', 0, 0, 'buy', 9, null, null, null, null),
(9, 'Ресурсы', '/projects/{id}/resources', 'fa fa-battery-quarter', 0, 0, 'resources', 10, 0, null, null, null),
(10, 'Документы', '/projects/{id}/docs', 'fa fa-paperclip', 1, 0, 'docs', 11, null, null, 1, 1),
(11, 'Обсуждение', '/projects/{id}/themes', 'fa fa-comments-o', 1, 1, 'themes', 14, null, null, 1, 1),
(12, 'Рабочее время', '/projects/{id}/timesheets', 'fa fa-clock-o', 1, 0, 'timesheets', 7, 1, null, null, null),
(13, 'Новости', '/projects/{id}/events', 'fa fa-newspaper-o', 1, 0, 'events', 13, null, null, null, null),
(14, 'Риски', '/projects/{id}/risks', 'fa fa-bolt', 1, 0, 'risks', 10, 1, null, null, null),
(15, 'Задачи', '/projects/{id}/tasks', 'fa fa-users', 1, 0, 'tasks', 12, null, null, null, 1),
(100, 'Результаты', '/projects/{id}/results', 'fa fa-magic', 1, 1, 'results', 100, null, null, null, null)
GO

-- SEED: PROJECTS_STATUSES
IF NOT EXISTS(SELECT 1 FROM PROJECTS_STATUSES)
INSERT INTO PROJECTS_STATUSES(STATUS_ID, NAME, IMG_URL, NOTE, IS_DEAL) VALUES
(-1, 'Удалено', null, null, null),
(0, 'Черновик', null, null, 0),
(1, 'Отбор', null, null, 0),
(2, 'Запуск', null, null, 0),
(3, 'Реализация', null, null, 0),
(4, 'Выход', null, null, 0),
(10, 'Завершено', null, null, 0),
(20, 'Черновик', null, null, 1),
(25, 'Производство', null, null, 1),
(26, 'Склад', null, null, 1),
(27, 'Дебиторка', null, null, 1),
(32, 'В работе', null, null, 1),
(33, 'Приостановлен', null, null, 1),
(34, 'Ошибка', null, null, 1),
(35, 'Исполнен', null, null, 1),
(40, 'Отменён', null, null, 1),
(50, 'Архив', null, null, 1)
GO

-- SEED: PROJECTS_TAGS_TYPES
IF NOT EXISTS(SELECT 1 FROM PROJECTS_TAGS_TYPES)
INSERT INTO PROJECTS_TAGS_TYPES(TYPE_ID, NAME) VALUES
(1, 'План проекта'),
(2, 'Документы')
GO

-- SEED: SDOCS_GOALS_STATUSES
IF NOT EXISTS(SELECT 1 FROM SDOCS_GOALS_STATUSES)
INSERT INTO SDOCS_GOALS_STATUSES(STATUS_ID, NAME) VALUES
(-2, 'Скрыто'),
(-1, 'Удалено'),
(1, 'Открыто'),
(2, 'Закрыто')
GO

-- SEED: SDOCS_MFR_CONTENTS_CANCELREASONS
IF NOT EXISTS(SELECT 1 FROM SDOCS_MFR_CONTENTS_CANCELREASONS)
INSERT INTO SDOCS_MFR_CONTENTS_CANCELREASONS(CANCEL_REASON_ID, NAME) VALUES
(0, 'Очистить признак'),
(1, 'Корректировка'),
(2, 'Экономия')
GO

-- SEED: SDOCS_MFR_DRAFTS_STATUSES
IF NOT EXISTS(SELECT 1 FROM SDOCS_MFR_DRAFTS_STATUSES)
INSERT INTO SDOCS_MFR_DRAFTS_STATUSES(STATUS_ID, NAME) VALUES
(-1, 'Удалено'),
(0, 'Черновик'),
(1, 'Поручено'),
(2, 'Исполнение'),
(3, 'Исполнено'),
(10, 'Принят'),
(100, 'Защищено')
GO

-- SEED: SDOCS_PROVIDES_GROUPS
IF NOT EXISTS(SELECT 1 FROM SDOCS_PROVIDES_GROUPS)
INSERT INTO SDOCS_PROVIDES_GROUPS(GROUP_ID, NAME) VALUES
(1, 'Заказы и запуски')
GO

-- SEED: SDOCS_PROVIDES_STATUSES
IF NOT EXISTS(SELECT 1 FROM SDOCS_PROVIDES_STATUSES)
INSERT INTO SDOCS_PROVIDES_STATUSES(STATUS_ID, NAME) VALUES
(0, '-'),
(1, 'Заказ'),
(2, 'Производство'),
(3, 'Склад'),
(4, 'Дебиторка')
GO

-- SEED: SDOCS_STATUSES
IF NOT EXISTS(SELECT 1 FROM SDOCS_STATUSES)
INSERT INTO SDOCS_STATUSES(STATUS_ID, NAME) VALUES
(-100, 'Архив'),
(-99, 'СТОП'),
(-1, 'Удалено'),
(0, 'Черновик'),
(1, 'Заявка'),
(2, 'Отправлено'),
(3, 'Обновление'),
(5, 'К оплате'),
(10, 'Исполнение'),
(20, 'Исполнено'),
(100, 'Закрыт')
GO

-- SEED: SDOCS_TYPES
IF NOT EXISTS(SELECT 1 FROM SDOCS_TYPES)
INSERT INTO SDOCS_TYPES(TYPE_ID, DIRECTION, NAME, NOTE) VALUES
(1, 0, 'Заказы', null),
(2, 0, 'Запуски', null),
(3, 0, 'Выпуски', null),
(4, 0, 'Отгрузка', null),
(5, 0, 'Пр.заказ', null),
(6, 0, 'Материалы', null),
(7, 0, 'Перемещение', null),
(8, 0, 'Счета поставщиков', null),
(9, 1, 'Поступление', null),
(10, 0, 'Передаточная накладная', 'TRF'),
(11, 0, 'Замены позиций', null),
(12, -1, 'Выдача', 'TRF'),
(13, 0, 'Перераспределение материалов', 'TRF'),
(14, -1, 'Продажа', 'TRF'),
(18, 0, 'Заявки на закупку', null),
(19, 1, 'Возврат', 'TRF'),
(20, 0, 'Брак производства', 'TRF'),
(100, 1, 'Инвентаризация', null)
GO

-- SEED: TASKS_PRIORITIES
IF NOT EXISTS(SELECT 1 FROM TASKS_PRIORITIES)
INSERT INTO TASKS_PRIORITIES(PRIORITY_ID, NAME, CSS_CLASS) VALUES
(0, 'Нет приоритета', 'fa fa-flag-o text-muted'),
(1, 'Критичная', 'fa fa-flag text-error'),
(2, 'Срочная', 'fa fa-flag text-warning'),
(3, 'Важная', 'fa fa-flag text-primary'),
(4, 'Несрочная', 'fa fa-flag text-muted')
GO

-- SEED: TASKS_STATUSES
IF NOT EXISTS(SELECT 1 FROM TASKS_STATUSES)
INSERT INTO TASKS_STATUSES(STATUS_ID, NAME, CSS_CLASS, IS_WORKING, CSS_BADGE) VALUES
(-30, 'Активные', 'fa fa-refresh', null, 'badge badge-primary bg-primary'),
(-20, 'Исходящие', 'fa fa-2x fa-paper-plane', null, 'badge badge-secondary bg-secondary'),
(-10, 'Входящие', 'fa fa-2x fa-inbox', null, 'badge badge-secondary bg-secondary'),
(-3, 'Отправлен запрос', 'fa fa-2x fa-comment-o', 1, 'badge badge-secondary bg-secondary'),
(-2, 'Отложить', 'fa fa-2x fa-map-pin', null, 'badge badge-secondary bg-secondary'),
(-1, 'Удалено', 'fa fa-2x fa-deleted', null, 'badge badge-secondary bg-secondary'),
(0, 'Черновик', 'fa fa-2x fa-file-o', null, 'badge text-muted'),
(1, 'Постановка', 'fa fa-2x fa-handshake-o', 1, 'badge badge-secondary bg-secondary'),
(2, 'Исполнение', 'fa fa-2x fa-user', 1, 'badge badge-secondary bg-secondary'),
(3, 'Проверка', 'fa fa-2x fa-retweet', 1, 'badge badge-secondary bg-secondary'),
(4, 'Приёмка', 'fa fa-2x fa-thumbs-o-up', 0, 'badge badge-success bg-success'),
(5, 'Завершено', 'fa fa-2x fa-check-circle', null, 'badge text-muted')
GO

-- SEED: TASKS_TYPES
IF NOT EXISTS(SELECT 1 FROM TASKS_TYPES)
INSERT INTO TASKS_TYPES(TYPE_ID, NAME) VALUES
(1, 'Задача'),
(2, 'Лист согласования'),
(3, 'Лист ознакомления'),
(10, 'Предоставление доступа')
GO

-- SEED: MOLS
-- DELETE FROM MOLS;
IF NOT EXISTS(SELECT 1 FROM MOLS WHERE MOL_ID = -25)
INSERT INTO MOLS(MOL_ID, NAME, SURNAME, EMAIL, IS_WORKING, STATUS_ID, DEPT_ID)
VALUES(-25, 'admin', 'admin', 'admin@mail.ru', 1, -2, 0)
GO

-- SEED: Users
-- delete users;
IF NOT EXISTS(SELECT 1 FROM Users)
INSERT INTO Users(Id,Email,PasswordHash,Salt,StatusId) VALUES
(-25, 'admin@dmail.ru', 'cJt/228sLnP6AIYsWnttOKj90bKPznIrr13vO2sIkaI==', 'J6xV7pQBotzi4PVYmiB2DQ==', 4)
-- login: admin, pwd: cispadmin
GO

-- SEED: Roles
;SET IDENTITY_INSERT Roles ON;
IF NOT EXISTS(SELECT 1 FROM Roles)
INSERT INTO Roles(Id, Name, Description) VALUES
(1, 'Admin', 'Администратор системы')
;SET IDENTITY_INSERT Roles OFF;
GO

-- SEED: UsersRoles
IF NOT EXISTS(SELECT 1 FROM UsersRoles)
INSERT INTO UsersRoles(UserId, RoleId) VALUES
(-25, 1)
GO
