module Products.Views exposing (details, list)

import BootstrapGallery as Gallery
import Dict exposing (Dict)
import Html exposing (..)
import Html.Attributes as A exposing (alt, attribute, class, for, href, id, selected, src, title, type_, value)
import Html.Events exposing (on, onSubmit, targetValue)
import Html.Extra exposing (viewIfLazy)
import Html.Keyed as Keyed
import Json.Decode as Decode
import Messages exposing (Msg(..))
import Model exposing (CartForms)
import Models.Fields exposing (Cents(..), centsToString, imageToSrcSet, imgSrcFallback, lotSizeToString)
import PageData exposing (ProductData)
import Paginate exposing (Paginated)
import Product exposing (Product, ProductId(..), ProductVariant, ProductVariantId(..), variantPrice)
import Products.Pagination as Pagination
import Products.Sorting as Sorting
import RemoteData
import Routing exposing (Route(..))
import SeedAttribute exposing (SeedAttribute)
import Views.Aria as Aria
import Views.Format as Format
import Views.Microdata as Microdata
import Views.Pager as Pager
import Views.Utils exposing (htmlOrBlank, icon, numericInput, onIntInput, rawHtml, routeLinkAttributes)


details : CartForms -> PageData.ProductDetails -> List (Html Msg)
details addToCartForms { product, variants, maybeSeedAttribute, categories } =
    let
        categoryBlocks =
            List.filter (not << String.isEmpty << .description) categories
                |> List.map
                    (\category ->
                        div [ class "product-category" ]
                            [ h3 [ class "mt-3" ]
                                [ a (routeLinkAttributes <| CategoryDetails category.slug Pagination.default)
                                    [ span [ Microdata.category ] [ text category.name ] ]
                                ]
                            , rawHtml category.description
                            ]
                    )
    in
    List.singleton <|
        div Microdata.product
            [ h1 [ class "product-details-title d-flex justify-content-between" ]
                [ Product.singleVariantName product variants
                , div [ class "d-none d-md-inline-flex" ]
                    [ htmlOrBlank SeedAttribute.icons maybeSeedAttribute ]
                ]
            , div [ class "d-md-none" ]
                [ htmlOrBlank SeedAttribute.icons maybeSeedAttribute ]
            , hr [] []
            , div [ class "product-details" ]
                [ div [ class "clearfix" ]
                    [ div [ class "product-image mr-md-3 mb-2" ]
                        [ div
                            [ class "card" ]
                            [ div [ class "card-body text-center p-1" ]
                                [ a
                                    [ href <| product.image.original
                                    , A.target "_self"
                                    , Gallery.openOnClick ProductDetailsLightbox product.image
                                    , Aria.label <| "View Product Image for " ++ product.name
                                    ]
                                    [ img
                                        [ src <| imgSrcFallback product.image
                                        , imageToSrcSet product.image
                                        , class "img-fluid mb-2"
                                        , alt <| "Product Image for " ++ product.name
                                        , Microdata.image
                                        , attribute "sizes" <|
                                            String.join ", "
                                                [ "(max-width: 767px) 100vw"
                                                , "(max-width: 991px) 125px"
                                                , "(max-width: 1199px) 230px"
                                                , "315px"
                                                ]
                                        ]
                                        []
                                    ]
                                , cartForm (cartFormData addToCartForms ( product, variants )) product
                                ]
                            ]
                        ]
                    , Microdata.mpnMeta product.baseSKU
                    , Microdata.skuMeta product.baseSKU
                    , Microdata.brandMeta "Southern Exposure Seed Exchange"
                    , Microdata.urlMeta <|
                        Routing.reverse <|
                            ProductDetails product.slug Nothing
                    , div [ Microdata.description ] [ rawHtml product.longDescription ]
                    , div [] categoryBlocks
                    ]
                ]
            ]


list : (Pagination.Data -> Route) -> Pagination.Data -> CartForms -> Paginated ProductData a c -> List (Html Msg)
list routeConstructor pagination addToCartForms products =
    let
        sortHtml =
            if productsCount > 1 then
                div [ class "d-flex mb-2 justify-content-between align-items-center" ]
                    [ sortingInput
                    , pager.perPageLinks ()
                    ]

            else
                text ""

        productsCount =
            Paginate.getTotalItems products

        sortingInput : Html Msg
        sortingInput =
            div [ class "form-inline products-sorting" ]
                [ label
                    [ class "col-form-label font-weight-bold d-none d-md-inline-block"
                    , for "product-sort-select"
                    ]
                    [ text "Sort by:" ]
                , text " "
                , select
                    [ id "product-sort-select"
                    , class "form-control form-control-sm ml-md-2"
                    , onProductsSortSelect (NavigateTo << routeConstructor)
                    , Aria.label "Select Products Sorting Method"
                    ]
                  <|
                    List.map
                        (\data ->
                            option
                                [ value <| Sorting.toQueryValue data
                                , selected (data == pagination.sorting)
                                ]
                                [ text <| Sorting.toDescription data ]
                        )
                        Sorting.all
                ]

        onProductsSortSelect : (Pagination.Data -> msg) -> Html.Attribute msg
        onProductsSortSelect msg =
            targetValue
                |> Decode.map
                    (\str ->
                        msg <|
                            { pagination | sorting = Sorting.fromQueryValue str }
                    )
                |> on "change"

        pager =
            Pager.elements
                { itemDescription = "Products"
                , pagerAriaLabel = "Category Product Pages"
                , pagerCssClass = "products-pagination"
                , pageSizes = [ 10, 25, 50, 75, 100 ]
                , routeConstructor =
                    \{ page, perPage } ->
                        routeConstructor { pagination | page = page, perPage = perPage }
                }
                products

        ( productRows, productBlocks ) =
            List.map
                (\(( p, v, _ ) as productData) ->
                    let
                        cartData =
                            cartFormData addToCartForms ( p, v )
                    in
                    ( renderProduct cartData productData
                    , renderMobileProductBlock cartData productData
                    )
                )
                (Paginate.getCurrent products)
                |> List.foldr (\( r, b ) ( rs, bs ) -> ( r :: rs, b :: bs )) ( [], [] )

        renderProduct cartData ( product, variants, maybeSeedAttribute ) =
            tr Microdata.product
                [ td [ class "row-product-image text-center align-middle" ]
                    [ Keyed.node "a"
                        (Aria.label ("View Details for " ++ product.name)
                            :: routeLinkAttributes (ProductDetails product.slug Nothing)
                        )
                        [ ( "product-img-" ++ (String.fromInt <| (\(ProductId i) -> i) product.id)
                          , img
                                [ src <| imgSrcFallback product.image
                                , imageToSrcSet product.image
                                , listImageSizes
                                , Microdata.image
                                , alt <| "Product Image for " ++ product.name
                                ]
                                []
                          )
                        ]
                    ]
                , td [ class "row-product-description" ]
                    [ h3 [ class "mb-0 d-flex justify-content-between" ]
                        [ a (Microdata.url :: routeLinkAttributes (ProductDetails product.slug Nothing))
                            [ Product.singleVariantName product variants ]
                        , htmlOrBlank SeedAttribute.icons maybeSeedAttribute
                        ]
                    , div [ Microdata.description ] [ rawHtml product.longDescription ]
                    , Microdata.mpnMeta product.baseSKU
                    , Microdata.skuMeta product.baseSKU
                    , Microdata.brandMeta "Southern Exposure Seed Exchange"
                    ]
                , td [ class "text-center align-middle" ]
                    [ cartForm cartData product ]
                ]

        mobileProductBlocks =
            div [ class "mobile-products-list d-md-none" ] productBlocks
    in
    if productsCount /= 0 then
        [ sortHtml
        , pager.viewTop ()
        , table [ class "products-table table table-striped table-sm mb-2 d-none d-md-table" ]
            [ tbody [] <| productRows ]
        , mobileProductBlocks
        , pager.viewBottom ()
        , SeedAttribute.legend
        ]

    else
        []


renderMobileProductBlock : CartFormData -> ( Product, Dict Int ProductVariant, Maybe SeedAttribute ) -> Html Msg
renderMobileProductBlock { maybeSelectedVariantId, maybeSelectedVariant, variantSelect, selectedItemNumber, quantity, isOutOfStock, requestFeedback } ( product, variants, maybeSeedAttribute ) =
    let
        formAttributes =
            (::) (class "row product-block") <|
                case maybeSelectedVariantId of
                    Just variantId ->
                        [ onSubmit <| SubmitAddToCart product.id variantId ]

                    Nothing ->
                        []

        inputAndButtonColumns =
            if isOutOfStock then
                []

            else
                [ div [ class "col-4 pr-0" ]
                    [ input
                        [ type_ "number"
                        , class "form-control"
                        , A.min "1"
                        , A.step "1"
                        , value <| String.fromInt quantity
                        , onIntInput <| ChangeCartFormQuantity product.id
                        , numericInput
                        , Aria.label "Quantity"
                        ]
                        []
                    ]
                , div [ class "col-8" ]
                    [ button [ class "btn btn-primary btn-block", type_ "submit" ]
                        [ text "Add to Cart" ]
                    ]
                , div [ class "col-12 mt-3 text-center" ] [ Html.map never requestFeedback ]
                ]

        availabilityBadge =
            if isOutOfStock then
                outOfStockBadge

            else
                text ""
    in
    form formAttributes <|
        [ div [ class "col-12 col-sm-4 pr-sm-0 mb-sm-2" ]
            [ Keyed.node "a"
                (Aria.label ("View Details for " ++ product.name)
                    :: routeLinkAttributes (ProductDetails product.slug Nothing)
                )
                [ ( "product-img-" ++ (String.fromInt <| (\(ProductId i) -> i) product.id)
                  , img
                        [ src <| imgSrcFallback product.image
                        , imageToSrcSet product.image
                        , class "img-fluid"
                        , listImageSizes
                        , alt <| "Product Image for " ++ product.name
                        ]
                        []
                  )
                ]
            ]
        , div [ class "col" ]
            [ h5 [ class "text-center text-sm-left" ]
                [ a (routeLinkAttributes <| ProductDetails product.slug Nothing)
                    [ Product.singleVariantName product variants ]
                ]
            , div [ class "price-and-attributes clearfix" ]
                [ htmlOrBlank renderPrice maybeSelectedVariant
                , small [ class "text-muted ml-2 d-inline-block" ]
                    [ text <| "Item #" ++ selectedItemNumber ]
                , htmlOrBlank SeedAttribute.icons maybeSeedAttribute
                ]
            , div [ class "d-none d-sm-block" ] [ variantSelect ]
            ]
        , div [ class "col-12 d-sm-none" ] [ variantSelect ]
        , div [ class "col-12 text-center" ] [ availabilityBadge ]
        ]
            ++ inputAndButtonColumns


listImageSizes : Html.Attribute msg
listImageSizes =
    attribute "sizes" <|
        String.join ", "
            [ "(max-width: 575px) 100vw"
            , "(max-width: 767px) 175px"
            , "100px"
            ]


renderPrice : ProductVariant -> Html msg
renderPrice variant =
    if variantPrice variant == Cents 0 then
        text "Free!"

    else
        case variant.salePrice of
            Just salePrice ->
                div [ class "sale-price" ]
                    [ Html.del [] [ text <| Format.cents variant.price ]
                    , div [ class "text-danger" ] [ text <| Format.cents salePrice ]
                    ]

            Nothing ->
                text <| Format.cents variant.price


outOfStockBadge : Html msg
outOfStockBadge =
    span [ class "badge badge-danger" ] [ text "Out of Stock" ]


limitedAvailabilityBadge : Html msg
limitedAvailabilityBadge =
    span [ class "badge badge-warning" ] [ text "Limited Availability" ]


cartForm : CartFormData -> Product -> Html Msg
cartForm { maybeSelectedVariant, maybeSelectedVariantId, quantity, isOutOfStock, variantSelect, selectedItemNumber, offersMeta, requestFeedback } product =
    let
        formAttributes =
            (::) (class "add-to-cart-form") <|
                case maybeSelectedVariantId of
                    Just variantId ->
                        [ onSubmit <| SubmitAddToCart product.id variantId ]

                    Nothing ->
                        []

        selectedPrice =
            maybeSelectedVariant
                |> htmlOrBlank (\v -> h4 [] [ renderPrice v ])

        addToCartInput _ =
            div [ class "input-group mx-auto justify-content-center add-to-cart-group mb-2" ]
                [ input
                    [ type_ "number"
                    , class "form-control"
                    , A.min "1"
                    , A.step "1"
                    , value <| String.fromInt quantity
                    , onIntInput <| ChangeCartFormQuantity product.id
                    , numericInput
                    , Aria.label "Quantity"
                    ]
                    []
                , div [ class "input-group-append" ]
                    [ button [ class "btn btn-primary", type_ "submit" ]
                        [ text "Add"
                        , span [ class "d-md-none" ] [ text " to Cart" ]
                        ]
                    ]
                ]

        availabilityBadge =
            if isOutOfStock then
                outOfStockBadge

            else
                text ""
    in
    form formAttributes
        [ selectedPrice
        , variantSelect
        , viewIfLazy (not isOutOfStock) addToCartInput
        , Html.map never requestFeedback
        , availabilityBadge
        , small [ class "text-muted d-block" ]
            [ text <| "Item #" ++ selectedItemNumber ]
        , Html.map never offersMeta
        ]


type alias CartFormData =
    { maybeSelectedVariant : Maybe ProductVariant
    , maybeSelectedVariantId : Maybe ProductVariantId
    , quantity : Int
    , isOutOfStock : Bool
    , isLimitedAvailablity : Bool
    , variantSelect : Html Msg
    , selectedItemNumber : String
    , offersMeta : Html Never
    , requestFeedback : Html Never
    }


cartFormData : CartForms -> ( Product, Dict Int ProductVariant ) -> CartFormData
cartFormData addToCartForms ( product, variants ) =
    let
        ( maybeSelectedVariantId, quantity, requestStatus ) =
            Dict.get (fromProductId product.id) addToCartForms
                |> Maybe.withDefault { variant = Nothing, quantity = 1, requestStatus = RemoteData.NotAsked }
                |> (\v -> ( v.variant |> ifNothing maybeFirstVariantId, v.quantity, v.requestStatus ))

        maybeSelectedVariant =
            maybeSelectedVariantId
                |> Maybe.andThen (\id -> Dict.get (fromVariantId id) variants)

        maybeFirstVariantId =
            variantList
                |> List.filter
                    (\v ->
                        if isOutOfStock then
                            True

                        else
                            v.quantity > 0
                    )
                |> List.sortBy .skuSuffix
                |> List.head
                |> Maybe.map .id

        isOutOfStock =
            Product.isOutOfStock variantList

        selectedItemNumber =
            case maybeSelectedVariant of
                Nothing ->
                    product.baseSKU

                Just v ->
                    product.baseSKU ++ v.skuSuffix

        showVariantSelect =
            Dict.size variants > 1

        variantSelect _ =
            select
                [ id <| "inputVariant-" ++ String.fromInt (fromProductId product.id)
                , class "variant-select form-control mb-1 mx-auto mr-sm-3 mx-md-auto"
                , title "Choose a Size"
                , onSelectInt <| ChangeCartFormVariantId product.id
                , Aria.label <| "Select a Lot Size Variant for " ++ product.name
                ]
                (List.map variantOption <| List.sortBy .skuSuffix variantList)

        onSelectInt msg =
            targetValue
                |> Decode.andThen
                    (String.toInt
                        >> Maybe.map (ProductVariantId >> Decode.succeed)
                        >> Maybe.withDefault (Decode.fail "")
                    )
                |> Decode.map msg
                |> on "change"

        variantOption variant =
            let
                isSelected =
                    Just variant == maybeSelectedVariant

                appendPrice s =
                    if isSelected then
                        [ s ]

                    else
                        [ s, Format.cents <| variantPrice variant ]

                appendOoS l =
                    if variant.quantity <= 0 then
                        l ++ [ "OoS" ]

                    else
                        l

                -- Disable the option unless the entire product is
                -- out-of-stock.
                disabledAttr =
                    if isOutOfStock then
                        []

                    else
                        [ A.disabled <| variant.quantity <= 0 ]
            in
            Maybe.map lotSizeToString variant.lotSize
                |> Maybe.withDefault (product.baseSKU ++ variant.skuSuffix)
                |> appendPrice
                |> appendOoS
                |> String.join " - "
                |> text
                |> List.singleton
                |> option
                    ([ value <| String.fromInt <| fromVariantId variant.id
                     , selected (Just variant == maybeSelectedVariant)
                     , A.classList [ ( "out-of-stock", variant.quantity <= 0 ) ]
                     ]
                        ++ disabledAttr
                    )

        variantList =
            Dict.values variants

        fromVariantId (ProductVariantId i) =
            i

        fromProductId (ProductId i) =
            i

        ifNothing valIfNothing maybe =
            case maybe of
                Just _ ->
                    maybe

                Nothing ->
                    valIfNothing

        offers =
            div [] <|
                List.map
                    renderOfferMeta
                    variantList

        renderOfferMeta variant =
            let
                availability =
                    if variant.quantity > 0 then
                        Microdata.InStock

                    else
                        Microdata.OutOfStock
            in
            div (Microdata.offers :: Microdata.offer)
                [ Microdata.availabilityMeta availability
                , Microdata.conditionMeta Microdata.NewCondition
                , Microdata.mpnMeta (product.baseSKU ++ variant.skuSuffix)
                , Microdata.skuMeta (product.baseSKU ++ variant.skuSuffix)
                , Microdata.priceMeta (centsToString variant.price)
                , Microdata.priceCurrencyMeta "USD"
                , Microdata.descriptionMeta <|
                    Maybe.withDefault "" <|
                        Maybe.map lotSizeToString variant.lotSize
                , Microdata.urlMeta <|
                    Routing.reverse <|
                        ProductDetails product.slug Nothing
                ]

        requestFeedback =
            case requestStatus of
                RemoteData.NotAsked ->
                    text ""

                RemoteData.Loading ->
                    div [ class "text-warning font-weight-bold small" ]
                        [ icon "spinner fa-spin mr-1"
                        , text "Adding to Cart"
                        ]

                RemoteData.Success _ ->
                    div [ class "text-success font-weight-bold small" ]
                        [ icon "check-circle mr-1"
                        , text "Added to Cart!"
                        ]

                RemoteData.Failure _ ->
                    div [ class "text-danger font-weight-bold small" ]
                        [ icon "times mr-1"
                        , text "Error Adding To Cart!"
                        ]
    in
    { maybeSelectedVariant = maybeSelectedVariant
    , maybeSelectedVariantId = maybeSelectedVariantId
    , quantity = quantity
    , isOutOfStock = Product.isOutOfStock variantList
    , isLimitedAvailablity = Product.isLimitedAvailablity variantList
    , variantSelect = viewIfLazy showVariantSelect variantSelect
    , selectedItemNumber = selectedItemNumber
    , offersMeta = offers
    , requestFeedback = requestFeedback
    }
