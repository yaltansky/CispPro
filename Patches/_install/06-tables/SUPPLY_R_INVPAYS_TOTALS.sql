/****** Object:  Table [SUPPLY_R_INVPAYS_TOTALS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF OBJECT_ID('SUPPLY_R_INVPAYS_TOTALS') IS NOT NULL DROP TABLE SUPPLY_R_INVPAYS_TOTALS
CREATE TABLE SUPPLY_R_INVPAYS_TOTALS(
	ROW_ID INT PRIMARY KEY,
	--
    ACC_REGISTER_ID INT,
    INV_ID INT,
    INV_MILESTONE_ID INT, -- Веха счёта
    MFR_DOC_ID INT NOT NULL,
    PRODUCT_ID INT,
	ITEM_ID INT NOT NULL,
    --    
    INV_DATE DATE, -- Дата счёта
    INV_CONDITION VARCHAR(20),
    INV_CONDITION_PAY VARCHAR(20),
    INV_CONDITION_FUND VARCHAR(20),
    INV_D_MFR DATE, -- Дата контрактации
    INV_D_MFR_TO DATE, -- Дата выдачи в производство
    INV_D_PLAN DATE, -- Дата оплаты (план)
    INV_MS_D_PLAN DATE, -- Дата по счёта (план)
    INV_Q FLOAT,
    INV_Q_SHIP FLOAT,
    --
    INV_VALUE FLOAT, -- сумма счёта
	FINDOC_VALUE FLOAT, -- оплачено
    INV_FUND_VALUE FLOAT, -- финансировано
    --
    D_CALC DATETIME DEFAULT GETDATE(),
    --
    INDEX IX_SUPPLY_R_INVPAYS_TOTALS (INV_ID, INV_MILESTONE_ID, MFR_DOC_ID, ITEM_ID)
)
GO

/****** Object:  Index [IX_SUPPLY_R_INVPAYS_TOTALS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[SUPPLY_R_INVPAYS_TOTALS]') AND name = N'IX_SUPPLY_R_INVPAYS_TOTALS')
CREATE NONCLUSTERED INDEX [IX_SUPPLY_R_INVPAYS_TOTALS] ON [SUPPLY_R_INVPAYS_TOTALS]
(
	[INV_ID] ASC,
	[INV_MILESTONE_ID] ASC,
	[MFR_DOC_ID] ASC,
	[ITEM_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
