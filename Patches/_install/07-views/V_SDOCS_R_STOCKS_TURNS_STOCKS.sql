﻿IF OBJECT_ID('V_SDOCS_R_STOCKS_TURNS_STOCKS') IS NOT NULL DROP VIEW V_SDOCS_R_STOCKS_TURNS_STOCKS
GO
-- SELECT * FROM V_SDOCS_R_STOCKS_TURNS_STOCKS
CREATE VIEW V_SDOCS_R_STOCKS_TURNS_STOCKS
AS

SELECT 
    X.MOL_ID,
    X.PRODUCT_ID, 
    ACC_REGISTER_ID = ISNULL(X.ACC_REGISTER_ID, 0),
    STOCK_ID = ISNULL(X.STOCK_ID, 0),
    STOCK_NAME = ISNULL(S.NAME, CONCAT('#склад', X.STOCK_ID)), 
    UNIT_NAME = U.NAME, 
    Q_START, Q_INPUT, Q_OUTPUT, Q_END
FROM (
    SELECT 
        MOL_ID, ACC_REGISTER_ID, PRODUCT_ID, STOCK_ID, UNIT_ID,
        Q_START = SUM(Q_START),
        Q_INPUT = SUM(Q_INPUT),
        Q_OUTPUT = SUM(Q_OUTPUT),
        Q_END = SUM(Q_END)
    FROM SDOCS_R_STOCKS_TURNS
    GROUP BY MOL_ID, ACC_REGISTER_ID, PRODUCT_ID, STOCK_ID, UNIT_ID
    ) X
    LEFT JOIN SDOCS_STOCKS S ON S.STOCK_ID = X.STOCK_ID
    JOIN PRODUCTS_UNITS U ON U.UNIT_ID = X.UNIT_ID
WHERE 
    ABS(Q_END) > 1E-4 OR Q_INPUT > 1E-4 OR Q_OUTPUT > 1E-4

GO
