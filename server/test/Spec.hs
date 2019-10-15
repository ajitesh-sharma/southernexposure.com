{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
-- TODO: Split into ModuleNameSpec.hs files & Gen.hs file.
import Data.Aeson (Result(Success), fromJSON, toJSON)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Monoid ((<>))
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Time (UTCTime(..), Day(..), DiffTime, secondsToDiffTime, getCurrentTime, fromGregorian)
import Database.Persist.Sql (Entity(..), ToBackendKey, SqlBackend, toSqlKey)
import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Numeric.Natural (Natural)
import Test.Tasty
import Test.Tasty.Hedgehog
import Test.Tasty.HUnit hiding (assert)
import Text.XML.Generator (Xml, Elem, doc, defaultDocInfo, xrender)
import Web.FormUrlEncoded (FromForm(..), urlDecodeForm, fromEntriesByKey)

import Models
import Models.Fields
import Routes.CommonData
import StoneEdge

import qualified StoneEdgeFixtures as SEF

main :: IO ()
main =
    defaultMain tests

tests :: TestTree
tests =
    testGroup "Tests"
         [ modelsFields
         , modelsUtils
         , commonData
         , stoneEdge
         ]


modelsFields :: TestTree
modelsFields =
    testGroup "Models.Fields Module"
        [ testProperty "LotSize Aeson Instances" $ testJSON genLotSize
        ]
  where
      testJSON gen = property $ do
          val <- forAll gen
          Success val === fromJSON (toJSON val)

modelsUtils :: TestTree
modelsUtils =
    testGroup "Models.Utils Module"
        [ truncateHtmlTests
        ]


truncateHtmlTests :: TestTree
truncateHtmlTests = testGroup "truncateHtml"
    [ testProperty "Empty Input Returns Empty Output" emptyInput
    , testCase "Input with Less Words than Count" shortInput
    , testCase "Input Exceeding Count" longInput
    , testCase "Inputs Exceeding Count Have Open Tags Closed" longInputClosesTags
    , testCase "Multiple Open Tags are Properly Closed" closesMultipleOpenTags
    , testCase "Inline Comments are Removed" inlineCommentsRemoved
    , testCase "Comments Don't Count Towards Truncation Status" commentsDontCountTowardsTruncation
    ]
  where
    emptyInput :: Property
    emptyInput = property $ do
        count <- forAll $ Gen.int $ Range.linear (-9999) 9999
        truncateHtml count "" === ("", False)
    shortInput :: Assertion
    shortInput =
        ("<p>a short description</p>", False) @=?
            truncateHtml 10 "<p>a short description</p>"
    longInput :: Assertion
    longInput =
        ("a long description", True) @=?
            truncateHtml 3 "a long description will be truncated"
    longInputClosesTags :: Assertion
    longInputClosesTags =
        ("<p>a long description</p>", True) @=?
            truncateHtml 3 "<p>a long description will have any open tags closed</p>"
    closesMultipleOpenTags :: Assertion
    closesMultipleOpenTags =
        ("<p>a long <b>description</b></p>", True) @=?
            truncateHtml 3 "<p>a long <b>description will have</b> any open tags closed</p>"
    inlineCommentsRemoved :: Assertion
    inlineCommentsRemoved =
        ("<p>an inline comment is removed</p>", True) @=?
            truncateHtml 5 "<p>an inline comment<!-- me! --> is removed from the text</p>"
    commentsDontCountTowardsTruncation :: Assertion
    commentsDontCountTowardsTruncation = do
        ("a short description", False) @=?
            truncateHtml 3 "a short description<!-- Comment is Removed -->"
        ("a short description here", True) @=?
            truncateHtml 4 "a short description<!-- Comment is Removed --> here but not this."



commonData :: TestTree
commonData =
    testGroup "CommonData Module"
        [ couponTests
        , priorityFeeTests
        , categorySaleTests
        , productSaleTests
        ]



-- COUPON
couponTests :: TestTree
couponTests = testGroup "Coupon Discount Calculations"
    [ testProperty "Free Shipping" freeShipping
    , testProperty "Free Shipping with no methods" freeShippingNoMethods
    , testProperty "Percentage Discount" percentageDiscount
    , testProperty "Flat Discount" flatDiscount
    ]
  where
    couponWithType :: CouponType -> Gen Coupon
    couponWithType couponType = do
        coupon <- genCoupon
        return $ coupon { couponDiscount = couponType }
    freeShipping :: Property
    freeShipping = property $ do
        coupon <- forAll $ couponWithType FreeShipping
        shippingCharge <- forAll genCartCharge
        calculateCouponDiscount coupon [shippingCharge] 0 === ccAmount shippingCharge
    freeShippingNoMethods :: Property
    freeShippingNoMethods = property $ do
        coupon <- forAll $ couponWithType FreeShipping
        calculateCouponDiscount coupon [] 0 === 0
    percentageDiscount :: Property
    percentageDiscount = property $ do
        coupon <- forAll genCoupon
        percent <- case couponDiscount coupon of
            PercentageDiscount wholePercent ->
                return wholePercent
            _ ->
                forAll genWholePercentage
        let coupon_ = coupon { couponDiscount = PercentageDiscount percent }
        subTotal <- fromCents <$> forAll genCents
        calculateCouponDiscount coupon_ [] subTotal
            === Cents (round (toRational subTotal * (fromIntegral percent % 100)))
    flatDiscount :: Property
    flatDiscount = property $ do
        coupon <- forAll genCoupon
        amount <- case couponDiscount coupon of
            FlatDiscount amt ->
                return amt
            _ ->
                (+ 1) <$> forAll genCents
        let coupon_ = coupon { couponDiscount = FlatDiscount amount }
        subTotal <- forAll genCents
        let result = calculateCouponDiscount coupon_ [] (fromCents subTotal)
        if amount > subTotal then result === subTotal else result === amount


-- PRIORITY S&H
priorityFeeTests :: TestTree
priorityFeeTests = testGroup "Priority S&H Calculations"
    [ testCase "No Shipping Methods" noMethods
    , testProperty "Priority S&H Not Available" noPriorityAvailable
    , testProperty "Fee Correctly Calculated" calculatedCorrectly
    , testCase "Only Flat Rate Calculation" onlyFlat
    , testCase "Only Percentage Rate Calculation" onlyPercent
    ]
  where
    noMethods :: Assertion
    noMethods =
        calculatePriorityFee [] 9001 @?= Nothing
    noPriorityAvailable :: Property
    noPriorityAvailable = property $ do
        method <- forAll genCartCharge
        (Cents subTotal) <- forAll genCents
        calculatePriorityFee [ShippingCharge method Nothing] subTotal === Nothing
    calculatedCorrectly :: Property
    calculatedCorrectly = property $ do
        method <- forAll genCartCharge
        pr@(PriorityShippingFee (Cents flat) percent) <- forAll genPriorityFee
        (Cents subTotal) <- forAll genCents
        let percentAmount = toRational subTotal * (fromIntegral percent % 100)
        calculatePriorityFee [ShippingCharge method $ Just pr] subTotal
            === Just (Cents $ round $ percentAmount + toRational flat)
    onlyFlat :: Assertion
    onlyFlat =
        calculatePriorityFee [makeShippingCharge (PriorityShippingFee 200 0)] 1000
            @?= Just 200
    onlyPercent :: Assertion
    onlyPercent =
        calculatePriorityFee [makeShippingCharge (PriorityShippingFee 0 10)] 1000
            @?= Just 100
    makeShippingCharge :: PriorityShippingFee -> ShippingCharge
    makeShippingCharge fee = ShippingCharge (CartCharge "" 900) (Just fee)


-- SALES
categorySaleTests :: TestTree
categorySaleTests = testGroup "Category Sale Calculations"
    [ testProperty "Flat Amount Is Subtracted From Price" testFlatLessThanPrice
    , testProperty "Flat Amount >= Price Makes Product Free" testFlatGreaterThanPrice
    , testProperty "Percentage Sale Calculations" testPercentageProperty
    , testCase "Percentage Sale Calculation" testPercentageUnit
    , testProperty "Overrides An Existing Sale Price If Cheaper" testOverridesSalePrice
    , testProperty "Doesn't Override An Existing Sale Price If More Expensive" testNoOverridesSalePrice
    ]
  where
    testFlatLessThanPrice :: Property
    testFlatLessThanPrice = property $ do
        variantEntity <- forAll $ genEntity genProductVariant
        let variantData = makeVariantData variantEntity Nothing
        saleAmount <- forAll $ genCentRange $ Range.linear 1 (fromCents (getVariantPrice variantData) - 1)
        sale <- forAll $ genCategorySale $ FlatSale saleAmount
        applyCategorySaleDiscount sale variantData
            === getVariantPrice variantData - saleAmount
    testFlatGreaterThanPrice :: Property
    testFlatGreaterThanPrice = property $ do
        variantEntity <- forAll $ genEntity genProductVariant
        let variantData = makeVariantData variantEntity Nothing
            price = fromCents $ getVariantPrice variantData
        saleAmount <- forAll $ genCentRange $ Range.linear price (price * 10)
        sale <- forAll $ genCategorySale $ FlatSale saleAmount
        applyCategorySaleDiscount sale variantData === 0
    testPercentageProperty :: Property
    testPercentageProperty = property $ do
        variantEntity <- forAll $ genEntity genProductVariant
        let variantData = makeVariantData variantEntity Nothing
        salePercent <- forAll genWholePercentage
        sale <- forAll $ genCategorySale $ PercentSale salePercent
        let discountPercent = 1 - (fromIntegral salePercent % 100)
        applyCategorySaleDiscount sale variantData ===
            Cents (round $ toRational (fromCents $ getVariantPrice variantData) * discountPercent)
    testPercentageUnit :: Assertion
    testPercentageUnit = do
        time <- getCurrentTime
        let variantData = makeVariantData (makeVariant 1000) Nothing
            sale = CategorySale "" (PercentSale 13) time time []
        applyCategorySaleDiscount sale variantData @?= 870
    testOverridesSalePrice :: Property
    testOverridesSalePrice = property $ do
        (variantEntity, price) <- forAll
            $ makeVariantWithPrice $ Range.linear 2000 5000
        let variantData = makeVariantData variantEntity (Just $ price - 1500)
        saleAmount <- forAll $ genCentRange $ Range.linear 1501 $ fromCents price
        sale <- forAll $ genCategorySale $ FlatSale saleAmount
        getVariantPrice (applyCategorySale sale variantData) === price - saleAmount
    testNoOverridesSalePrice :: Property
    testNoOverridesSalePrice = property $ do
        (variantEntity, price) <- forAll
            $ makeVariantWithPrice $ Range.linear 2000 5000
        let variantData = makeVariantData variantEntity (Just 200)
        sale <- forAll $ do
            let price_ = fromCents price
            amount <- genCentRange $ Range.linear 0 (price_ - 199)
            genCategorySale $ FlatSale amount
        getVariantPrice (applyCategorySale sale variantData) === 200
    makeVariant :: Cents -> Entity ProductVariant
    makeVariant price =
        Entity (toSqlKey 1)
            $ ProductVariant (toSqlKey 1) "" price 1 (Just . Mass $ Milligrams 1) True
    makeVariantWithPrice :: Range Natural -> Gen (Entity ProductVariant, Cents)
    makeVariantWithPrice priceRange = do
        entity <- genProductVariant
        key <- genEntityKey
        price <- genCentRange priceRange
        let entityWithPrice = entity { productVariantPrice = price }
        return (Entity key entityWithPrice, price)

productSaleTests :: TestTree
productSaleTests = testGroup "Product Sale Calculations"
    [ testProperty "Sale Price Set If Less Than Price" testSalePrice
    , testProperty "Sale Price Not Set If Greater Than or Equal to Price" testNoSalePrice
    ]
  where
    testSalePrice :: Property
    testSalePrice = property $ do
        variant <- forAll $ genEntity genProductVariant
        let normalPrice = productVariantPrice $ entityVal variant
        salePrice <- forAll $ genCentRange $ Range.linear 0 (fromCents normalPrice - 1)
        getVariantPrice (makeVariantData variant $ Just salePrice) === salePrice
    testNoSalePrice :: Property
    testNoSalePrice = property $ do
        variant <- forAll $ genEntity genProductVariant
        let normalPrice = fromCents $ productVariantPrice $ entityVal variant
        salePrice <- forAll $ genCentRange $ Range.linear (normalPrice + 1) (normalPrice * 10)
        getVariantPrice (makeVariantData variant $ Just salePrice)
            === Cents normalPrice


-- STONE EDGE
stoneEdge :: TestTree
stoneEdge = testGroup "StoneEdge Module"
    [ errorTests
    , sendVersionTests
    , orderCountTests
    , downloadOrdersTests
    ]
  where
    errorTests :: TestTree
    errorTests = testGroup "SETI Errors"
        [ testCase "Simple Error Rendering" simpleErrorRendering
        , testCase "XML Error Rendering" xmlErrorRendering
        ]
    simpleErrorRendering :: Assertion
    simpleErrorRendering =
        renderSimpleSETIError "test error message"
            @?= "SETIError: test error message"
    xmlErrorRendering :: Assertion
    xmlErrorRendering =
        renderXmlSETIError Orders "test error message"
            @?= SEF.ordersErrorXml
    sendVersionTests :: TestTree
    sendVersionTests = testGroup "SendVersion SETI Function"
        [ testCase "Form Parsing" sendVersionParsing
        , testCase "Response Rendering" sendVersionResponse
        ]
    sendVersionParsing :: Assertion
    sendVersionParsing =
        testFormParsing "setifunction=sendversion&omversion=6.000"
            $ SendVersionRequest "6.000"
    sendVersionResponse :: Assertion
    sendVersionResponse =
        renderSendVersionResponse (SendVersionResponse "5.900")
            @?= "SETIResponse: version=5.900"
    orderCountTests :: TestTree
    orderCountTests = testGroup "OrderCount SETI Function"
        [ testCase "Form Parsing" orderCountParsing
        , testCase "Response Rendering" orderCountResponse
        ]
    orderCountParsing :: Assertion
    orderCountParsing =
        testFormParsing "setifunction=ordercount&setiuser=auser&password=pwd&code=mystore&lastorder=1001&lastdate=10-Jun-2003&omversion=5.000"
            $ OrderCountRequest "auser" "pwd" "mystore" (LastOrderNumber 1001)
                (LastDate $ fromGregorian 2003 6 10)
                "5.000"
    orderCountResponse :: Assertion
    orderCountResponse =
        renderOrderCountResponse (OrderCountResponse 42)
            @?= "SETIResponse: ordercount=42"
    downloadOrdersTests :: TestTree
    downloadOrdersTests = testGroup "DownloadOrders SETI Function"
        [ testCase "Form Parsing" downloadOrdersParsing
        , testCase "Form Parsing - No Decryption Key" downloadOrdersParsingNoKey
        , testCase "Response Rendering - No Orders" noOrdersResponse
        , testCase "Response Rendering - With Order" downloadOrdersResponse
        , testCase "Response Rendering - Billing XML" orderBillingResponse
        , testCase "Response Rendering - Shipping XML" orderShippingResponse
        , testCase "Response Rendering - CreditCard XML" paymentCreditCardResponse
        , testCase "Response Rendering - StoreCredit XML" paymentStoreCreditResponse
        , testCase "Response Rendering - Totals XML" orderTotalsResponse
        , testCase "Response Rendering - Coupon XML" orderCouponResponse
        , testCase "Response Rendering - OtherData XML" otherDataResponse
        ]
    downloadOrdersParsing :: Assertion
    downloadOrdersParsing =
        testFormParsing "setifunction=downloadorders&setiuser=auser&password=pwd&code=mystore&lastorder=1001&lastdate=10-Jun-2003&startnum=1&batchsize=100&dkey=decryptionkey&omversion=5.000"
            $ DownloadOrdersRequest "auser" "pwd" "mystore" (LastOrderNumber 1001)
                (LastDate $ fromGregorian 2003 6 10) 1 100 (Just "decryptionkey")
                "5.000"
    downloadOrdersParsingNoKey :: Assertion
    downloadOrdersParsingNoKey =
        testFormParsing "setifunction=downloadorders&setiuser=auser&password=pwd&code=mystore&lastorder=1001&lastdate=10-Jun-2003&startnum=1&batchsize=100&omversion=5.000"
            $ DownloadOrdersRequest "auser" "pwd" "mystore" (LastOrderNumber 1001)
                (LastDate $ fromGregorian 2003 6 10) 1 100 Nothing
                "5.000"
    noOrdersResponse :: Assertion
    noOrdersResponse =
        renderDownloadOrdersResponse NoOrdersToDownload @?=
            SEF.noOrdersXml
    downloadOrdersResponse :: Assertion
    downloadOrdersResponse =
        SEF.downloadOrdersXml @=?
            renderDownloadOrdersResponse (DownloadOrdersResponse
                [ StoneEdgeOrder
                    9001
                    (UTCTime (fromGregorian 2003 6 10) $ secondsToDiffTime 0)
                    (Just "Payment Received")
                    orderBilling
                    orderShipping
                    [orderCreditCard, orderStoreCredit]
                    orderTotals
                    [orderCoupon]
                    orderOtherData
                ]
            )
    orderBillingResponse :: Assertion
    orderBillingResponse =
        testXmlPart SEF.orderBillingXml
            $ renderStoneEdgeOrderBilling orderBilling
    orderBilling :: StoneEdgeOrderBilling
    orderBilling =
        StoneEdgeOrderBilling
            "Kevin Smith"
            (Just "Stone Edge Technologies  Inc.")
            (Just "215-641-1837")
            (Just "kevin@stoneedge.com")
            (StoneEdgeOrderAddress
                "One Valley Square"
                (Just "Suite 130")
                "Blue Bell"
                "PA"
                "19422"
                (Just "US")
            )
    orderShippingResponse :: Assertion
    orderShippingResponse =
        testXmlPart SEF.orderShippingXml
            $ renderStoneEdgeOrderShipping orderShipping
    orderShipping :: StoneEdgeOrderShipping
    orderShipping =
        StoneEdgeOrderShipping
            "Kevin Smith"
            (Just "Stone Edge Technologies  Inc.")
            (Just "215-641-1837")
            (Just "kevin@stoneedge.com")
            (StoneEdgeOrderAddress
                "One Valley Square"
                (Just "Suite 130")
                "Blue Bell"
                "PA"
                "19422"
                (Just "US")
            )
            [ StoneEdgeOrderProduct
                "SHRT"
                "MyShirt"
                1
                (StoneEdgeCents 500)
                (Just TangibleProduct)
                (Just True)
                (Just 125487)
                (Just $ StoneEdgeCents 500)

            ]
    paymentCreditCardResponse :: Assertion
    paymentCreditCardResponse =
        testXmlPart SEF.paymentCreditCardXml
            $ renderStoneEdgeOrderPayment orderCreditCard
    orderCreditCard :: StoneEdgeOrderPayment
    orderCreditCard =
        StoneEdgeOrderCreditCard $ StoneEdgePaymentCreditCard
            "Visa"
            (Just "9001")
            (Just "4729238728739452876")
            (Just $ StoneEdgeCents 9001)
    paymentStoreCreditResponse :: Assertion
    paymentStoreCreditResponse =
        testXmlPart SEF.paymentStoreCreditXml
            $ renderStoneEdgeOrderPayment orderStoreCredit
    orderStoreCredit :: StoneEdgeOrderPayment
    orderStoreCredit = StoneEdgeOrderStoreCredit
            $ StoneEdgePaymentStoreCredit
                (StoneEdgeCents 9001)
                (Just "Store Credit Description!")
    orderTotalsResponse :: Assertion
    orderTotalsResponse =
        testXmlPart SEF.orderTotalsXml
            $ renderStoneEdgeTotals orderTotals
    orderTotals :: StoneEdgeTotals
    orderTotals =
        StoneEdgeTotals
            (StoneEdgeCents 2500)
            [ StoneEdgeDiscount
                (Just SEFlatDiscount)
                (Just "5 Dollars Off")
                Nothing
                (StoneEdgeCents 500)
                (Just True)
            ]
            (StoneEdgeCents 2000)
            (Just $ StoneEdgeTax
                (StoneEdgeCents 268)
                (Just 0.05)
                (Just False)
                Nothing
                Nothing
            )
            (StoneEdgeCents 6443)
            [ StoneEdgeSurcharge
                (StoneEdgeCents 400)
                (Just "Fall Item Surcharge")
            ]
            (Just $ StoneEdgeShippingTotal
                (StoneEdgeCents 825)
                (Just "Ground")
            )
    orderCouponResponse :: Assertion
    orderCouponResponse =
        testXmlPart SEF.orderCouponXml
            $ renderStoneEdgeCoupon orderCoupon
    orderCoupon :: StoneEdgeCoupon
    orderCoupon =
        StoneEdgeCoupon
            "ABCCOUPON123"
            (Just "5% Off to HHF Customers")
            (StoneEdgeCents 420)
            (Just True)
    otherDataResponse :: Assertion
    otherDataResponse =
        testXmlPart SEF.orderOtherDataXml
            $ renderStoneEdgeOtherData orderOtherData
    orderOtherData :: StoneEdgeOtherData
    orderOtherData =
        StoneEdgeOtherData
            (Just "Priority Shipping")
            (Just "Long, Multiline\nCustomer Comments")
            (Just 9001)
    -- | Render an XML element & ensure it matches the expected output.
    testXmlPart :: BS.ByteString -> Xml Elem -> Assertion
    testXmlPart expected element =
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" <> expected
            @=?  xrender (doc defaultDocInfo element)



-- UTILITIES


-- | Assert parsing of a FormUrlEncoded value decodes to the proper value.
testFormParsing :: (FromForm a, Eq a, Show a) => LBS.ByteString -> a -> Assertion
testFormParsing urlData expected =
    (urlDecodeForm urlData >>= fromForm) @?= Right expected



-- GENERATORS


-- Generate an active coupon with minimum order size of 0 to $10.00
genCoupon :: Gen Coupon
genCoupon =
    Coupon
        <$> genText
        <*> genText
        <*> genText
        <*> pure True
        <*> genCouponType
        <*> genCentRange (Range.linear 0 1000)
        <*> genUTCTime
        <*> pure 0
        <*> pure 0
        <*> genUTCTime

genCouponType :: Gen CouponType
genCouponType =
    Gen.choice
        [ FlatDiscount <$> genCents
        , PercentageDiscount <$> genWholePercentage
        , pure FreeShipping
        ]

-- Generate charges of $0.01 to $10.00
genCartCharge :: Gen CartCharge
genCartCharge =
    CartCharge
        <$> genText
        <*> genCentRange (Range.linear 1 1000)

genPriorityFee :: Gen PriorityShippingFee
genPriorityFee =
    PriorityShippingFee
        <$> genCentRange (Range.linear 1 1000)
        <*> genWholePercentage

genProductVariant :: Gen ProductVariant
genProductVariant =
    ProductVariant
        <$> fmap toSqlKey (Gen.integral $ Range.linear 1 100)
        <*> genText
        <*> genCentRange (Range.linear 1 999999)
        <*> Gen.integral (Range.linear 1 1000)
        <*> Gen.maybe genLotSize
        <*> Gen.bool

genCategorySale :: SaleType -> Gen CategorySale
genCategorySale saleType =
    CategorySale
        <$> genText
        <*> pure saleType
        <*> genUTCTime
        <*> genUTCTime
        <*> Gen.list (Range.linear 1 10) genEntityKey


genEntity :: (ToBackendKey SqlBackend a) => Gen a -> Gen (Entity a)
genEntity genModel =
    Entity <$> genEntityKey <*> genModel


genEntityKey :: (ToBackendKey SqlBackend a) => Gen (Key a)
genEntityKey =
    toSqlKey <$> Gen.int64 (Range.linear 1 1000)


genCentRange :: Range Natural -> Gen Cents
genCentRange r =
    Cents <$> Gen.integral r

genCents :: Gen Cents
genCents = genCentRange $ Range.linear 0 999999

genLotSize :: Gen LotSize
genLotSize =
    Gen.choice
        [ Mass <$> genMilligrams
        , Bulbs <$> genInt
        , Slips <$> genInt
        , Plugs <$> genInt
        , CustomLotSize <$> genText
        ]
  where
    genInt =
        Gen.integral $ Range.linear 1 1000
    genMilligrams =
        Milligrams <$> Gen.integral (Range.linear 1 454000)

genWholePercentage :: Gen Percent
genWholePercentage = Gen.integral $ Range.linear 1 100

genText :: MonadGen m => m Text
genText = Gen.text (Range.linear 1 10) Gen.alpha

genUTCTime :: Gen UTCTime
genUTCTime =
    UTCTime
        <$> genDay
        <*> genTime
  where
    genDay :: Gen Day
    genDay = ModifiedJulianDay <$> Gen.integral (Range.linear 0 999999)
    genTime :: Gen DiffTime
    genTime = secondsToDiffTime <$> Gen.integral (Range.linear 0 86400)
