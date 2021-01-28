/************************************************************

    CURRENCY and EXCHANGE RATE manager.
    This is simple, but smart way to find out exchange rate between currencies
    It can handle buy, sale and middle rate types. 
    It can manage invers rates by types.
    It can manage cross rates by types.
    There are two tables only and one view.
    The view shows all exchange rates and their inverses too.

    The most important and smart part of this solution is the GET_EXCHANGE_RATE function.
    This function does the best what it can.
    If there is exact exhange rate between two currencies at the given date, it will return with this.
    But if there is not direct and exact data, it tries to find first a cross (one step) and next a two steps cross way between the two currencies.
    In this case the result will be a negative number to show this is not an exact value but only a calculated one.

    Along this method we can manage unit exchanges as well. 

    History of changes
    yyyy.mm.dd | Version | Author   | Changes
    -----------+---------+----------+-------------------------
    2016.10.16 |  1.0    | Tothf    | Created 

************************************************************/


------------------
-- TABLES
------------------
CREATE TABLE CE_CURRENCIES (
    CODE                    VARCHAR2 (   50 ) NOT NULL,
    NAME                    VARCHAR2 (  500 ) NOT NULL,
    VALID_TO                DATE,
    CONSTRAINT              PK_CE_CURRENCIES     PRIMARY KEY ( CODE )
  );


CREATE TABLE CE_EXCHANGE_RATES (
    CURRENCY_CODE_FROM      VARCHAR2 ( 50 ) NOT NULL,
    CURRENCY_CODE_TO        VARCHAR2 ( 50 ) NOT NULL,
    VALID_FROM              DATE            NOT NULL,
    RATE_BUY                NUMBER,
    RATE_SALE               NUMBER,
    RATE_MIDDLE             NUMBER,
    REMARK                  VARCHAR2 ( 2000 ),
    CONSTRAINT              PK_CE_EXCHANGE_RATES     PRIMARY KEY ( CURRENCY_CODE_FROM, CURRENCY_CODE_TO, VALID_FROM ),
    CONSTRAINT              FK1_CE_EXCHANGE_RATES    FOREIGN KEY ( CURRENCY_CODE_FROM ) REFERENCES CE_CURRENCIES  ( CODE ),
    CONSTRAINT              FK2_CE_EXCHANGE_RATES    FOREIGN KEY ( CURRENCY_CODE_TO   ) REFERENCES CE_CURRENCIES  ( CODE )
  );



------------------
-- VIEW
------------------
CREATE OR REPLACE VIEW CE_EXCHANGE_RATES_VW AS
SELECT CURRENCY_CODE_FROM, CURRENCY_CODE_TO, VALID_FROM, REMARK,   RATE_SALE,   RATE_BUY,   RATE_MIDDLE FROM CE_EXCHANGE_RATES 
UNION ALL
SELECT CURRENCY_CODE_TO, CURRENCY_CODE_FROM, VALID_FROM, REMARK, 1/RATE_SALE, 1/RATE_BUY, 1/RATE_MIDDLE FROM CE_EXCHANGE_RATES 
;


------------------
-- FUNCTION
------------------
create or replace function GET_EXCHANGE_RATE ( I_CURRENCY_CODE_FROM  in varchar2
                                             , I_CURRENCY_CODE_TO    in varchar2
                                             , I_SBM                 in varchar2 default 'ANY'  /* SALE, BUY, MIDDLE, ANY */
                                             , I_VALID_FROM          in date     default null
                                             ) return number is

    V_CURRENCY_CODE_FROM    varchar2( 50 ) := trim( upper( I_CURRENCY_CODE_FROM ) );
    V_CURRENCY_CODE_TO      varchar2( 50 ) := trim( upper( I_CURRENCY_CODE_TO   ) );
    V_VALID_FROM            date           := nvl( I_VALID_FROM, sysdate) ;
    V_SBM                   varchar2( 50 ) := trim( upper( I_SBM ) );
    V_RATE_BUY              number;
    V_RATE_SALE             number;
    V_RATE_MIDDLE           number;

begin
--    dbms_output.put_line( V_CURRENCY_CODE_FROM||' -> '||V_CURRENCY_CODE_TO);

    if I_CURRENCY_CODE_FROM is null or I_CURRENCY_CODE_TO is null then
        return null;
    end if;

    if I_CURRENCY_CODE_FROM = I_CURRENCY_CODE_TO then
        return 1;
    end if;

    if V_SBM not in ( 'SALE', 'BUY', 'MIDDLE') then
        V_SBM := 'ANY';
    end if;

    -- is a direct link?
    select avg( RATE_SALE ), avg( RATE_BUY ), avg( RATE_MIDDLE )
      into    V_RATE_SALE  ,    V_RATE_BUY,      V_RATE_MIDDLE
      from CE_EXCHANGE_RATES_VW K
     where CURRENCY_CODE_FROM = V_CURRENCY_CODE_FROM
       and CURRENCY_CODE_TO   = V_CURRENCY_CODE_TO
       and VALID_FROM         = ( select max( VALID_FROM ) 
                                    from CE_EXCHANGE_RATES_VW B
                                   where CURRENCY_CODE_FROM = K.CURRENCY_CODE_FROM
                                     and CURRENCY_CODE_TO   = K.CURRENCY_CODE_TO
                                     and VALID_FROM        <= V_VALID_FROM
                                );

    if ( V_SBM = 'SALE'   and V_RATE_SALE   is null ) or
       ( V_SBM = 'BUY'    and V_RATE_BUY    is null ) or
       ( V_SBM = 'MIDDLE' and V_RATE_MIDDLE is null ) or
       ( V_SBM = 'ANY'    and V_RATE_SALE   is null and V_RATE_BUY is null and V_RATE_MIDDLE is null ) then

        -- is a undirect link via 1 step?
        select avg( A1.RATE_SALE * A2.RATE_SALE ), avg( A1.RATE_BUY * A2.RATE_BUY ), avg( A1.RATE_MIDDLE * A2.RATE_MIDDLE ) 
          into V_RATE_SALE, V_RATE_BUY, V_RATE_MIDDLE
          from ( select *
                   from CE_EXCHANGE_RATES_VW K
                  where CURRENCY_CODE_FROM = V_CURRENCY_CODE_FROM
                    and VALID_FROM         = ( select max( VALID_FROM ) 
                                                 from CE_EXCHANGE_RATES_VW B
                                                where CURRENCY_CODE_FROM = K.CURRENCY_CODE_FROM
                                                  and CURRENCY_CODE_TO   = K.CURRENCY_CODE_TO
                                                  and VALID_FROM        <= V_VALID_FROM
                                             )
               ) A1
               ,
               ( select *
                 from CE_EXCHANGE_RATES_VW K
                where CURRENCY_CODE_TO   = V_CURRENCY_CODE_TO
                  and VALID_FROM         = ( select max( VALID_FROM ) 
                                               from CE_EXCHANGE_RATES_VW B
                                              where CURRENCY_CODE_FROM = K.CURRENCY_CODE_FROM
                                                and CURRENCY_CODE_TO   = K.CURRENCY_CODE_TO
                                                and VALID_FROM        <= V_VALID_FROM
                                           )
               ) A2
         where A1.CURRENCY_CODE_TO = A2.CURRENCY_CODE_FROM;          

        if ( V_SBM = 'SALE'   and V_RATE_SALE   is null ) or
           ( V_SBM = 'BUY'    and V_RATE_BUY    is null ) or
           ( V_SBM = 'MIDDLE' and V_RATE_MIDDLE is null ) or
           ( V_SBM = 'ANY'    and V_RATE_SALE   is null and V_RATE_BUY is null and V_RATE_MIDDLE is null ) then
      
            -- is a undirect link via 2 steps?

            -- select A1.CURRENCY_CODE_FROM, A2.CURRENCY_CODE_FROM VIA_FROM, A2.CURRENCY_CODE_TO VIA_TO, A3.CURRENCY_CODE_TO, A1.RATE * A2.RATE * A3.RATE from 
      
            select avg( A1.RATE_SALE * A2.RATE_SALE * A3.RATE_SALE ), avg( A1.RATE_BUY * A2.RATE_BUY * A3.RATE_BUY ), avg( A1.RATE_MIDDLE * A2.RATE_MIDDLE * A3.RATE_MIDDLE ) 
              into V_RATE_SALE, V_RATE_BUY, V_RATE_MIDDLE
              from ( select *
                       from CE_EXCHANGE_RATES_VW K
                      where CURRENCY_CODE_FROM = V_CURRENCY_CODE_FROM
                        and VALID_FROM         = ( select max( VALID_FROM ) 
                                                     from CE_EXCHANGE_RATES_VW B
                                                    where CURRENCY_CODE_FROM = K.CURRENCY_CODE_FROM
                                                      and CURRENCY_CODE_TO   = K.CURRENCY_CODE_TO
                                                      and VALID_FROM        <= V_VALID_FROM
                                                 )
                   ) A1
                   ,
                   ( select *
                     from CE_EXCHANGE_RATES_VW K
                    where VALID_FROM         = ( select max( VALID_FROM ) 
                                                   from CE_EXCHANGE_RATES_VW B
                                                  where CURRENCY_CODE_FROM = K.CURRENCY_CODE_FROM
                                                    and CURRENCY_CODE_TO   = K.CURRENCY_CODE_TO
                                                    and VALID_FROM        <= V_VALID_FROM
                                               )
                   ) A2
                   ,
                   ( select *
                     from CE_EXCHANGE_RATES_VW K
                    where CURRENCY_CODE_TO   = V_CURRENCY_CODE_TO
                      and VALID_FROM         = ( select max( VALID_FROM ) 
                                                   from CE_EXCHANGE_RATES_VW B
                                                  where CURRENCY_CODE_FROM = K.CURRENCY_CODE_FROM
                                                    and CURRENCY_CODE_TO   = K.CURRENCY_CODE_TO
                                                    and VALID_FROM        <= V_VALID_FROM
                                               )
                   ) A3
             where A1.CURRENCY_CODE_TO = A2.CURRENCY_CODE_FROM
               and A2.CURRENCY_CODE_TO = A3.CURRENCY_CODE_FROM;
                     
        end if;

        V_RATE_SALE  := -1 * V_RATE_SALE  ;
        V_RATE_BUY   := -1 * V_RATE_BUY   ;
        V_RATE_MIDDLE:= -1 * V_RATE_MIDDLE;
      
    end if;

    case V_SBM 
        when 'SALE'   then return V_RATE_SALE  ;
        when 'BUY'    then return V_RATE_BUY   ;
        when 'MIDDLE' then return V_RATE_MIDDLE;
        else return coalesce( V_RATE_MIDDLE, V_RATE_SALE, V_RATE_BUY );
    end case;

end;
/




------------------
-- TEST
------------------
INSERT INTO CE_CURRENCIES ( CODE, NAME             ) VALUES ( 'HUF',  'Hungarian Forint'       );                    
INSERT INTO CE_CURRENCIES ( CODE, NAME             ) VALUES ( 'EUR',  'Euro'                   ); 
INSERT INTO CE_CURRENCIES ( CODE, NAME             ) VALUES ( 'USD',  'United States Dollar'   );
INSERT INTO CE_CURRENCIES ( CODE, NAME             ) VALUES ( 'GBP',  'United Kingdom Pound'   );


INSERT INTO CE_EXCHANGE_RATES ( CURRENCY_CODE_FROM, CURRENCY_CODE_TO, VALID_FROM, RATE_BUY             ) VALUES ( 'EUR',  'HUF', TO_DATE('2016.01.01', 'YYYY.MM.DD'), 300 );                    
INSERT INTO CE_EXCHANGE_RATES ( CURRENCY_CODE_FROM, CURRENCY_CODE_TO, VALID_FROM, RATE_BUY, RATE_SALE  ) VALUES ( 'USD',  'EUR', TO_DATE('2016.02.01', 'YYYY.MM.DD'), 0.8, 0.7 );                    
INSERT INTO CE_EXCHANGE_RATES ( CURRENCY_CODE_FROM, CURRENCY_CODE_TO, VALID_FROM, RATE_SALE            ) VALUES ( 'USD',  'GBP', TO_DATE('2016.03.01', 'YYYY.MM.DD'), 0.5 );                    
COMMIT;

select GET_EXCHANGE_RATE ( 'HUF','EUR' ) from dual;
select GET_EXCHANGE_RATE ( 'EUR','HUF' ) from dual;
select GET_EXCHANGE_RATE ( 'USD','HUF' ) from dual;
select GET_EXCHANGE_RATE ( 'GBP','EUR' ) from dual;
select GET_EXCHANGE_RATE ( 'GBP','EUR', 'BUY' ) from dual;
select GET_EXCHANGE_RATE ( 'GBP','EUR', 'SALE' ) from dual;


GET_EXCHANGE_RATE('HUF','EUR')
------------------------------
                  .00333333333 

GET_EXCHANGE_RATE('EUR','HUF')
------------------------------
                           300 

GET_EXCHANGE_RATE('USD','HUF')
------------------------------
                          -240 

GET_EXCHANGE_RATE('GBP','EUR')
------------------------------
                          -1.4 

GET_EXCHANGE_RATE('GBP','EUR','BUY')
------------------------------------
                                    

GET_EXCHANGE_RATE('GBP','EUR','SALE')
-------------------------------------
                                 -1.4 
 


