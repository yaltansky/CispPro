IF NOT EXISTS(SELECT 1 FROM SYS.FULLTEXT_CATALOGS WHERE NAME = 'CATALOG')
CREATE FULLTEXT CATALOG [CATALOG] WITH ACCENT_SENSITIVITY = OFF
AS DEFAULT

GO
