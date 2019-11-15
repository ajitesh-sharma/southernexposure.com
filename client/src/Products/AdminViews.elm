module Products.AdminViews exposing
    ( ListForm
    , ListMsg
    , NewForm
    , NewMsg
    , initialListForm
    , initialNewForm
    , list
    , new
    , updateListForm
    , updateNewForm
    )

import Api
import Array exposing (Array)
import Category exposing (CategoryId(..))
import Dict
import File exposing (File)
import Html exposing (Html, a, br, button, div, fieldset, form, h3, hr, input, label, option, select, span, table, tbody, td, text, th, thead, tr)
import Html.Attributes as A exposing (checked, class, for, id, name, required, selected, step, type_, value)
import Html.Events exposing (on, onCheck, onClick, onInput, onSubmit, targetValue)
import Json.Decode as Decode
import Json.Encode as Encode
import Models.Fields exposing (Cents(..), LotSize(..), centsEncoder, centsFromString, lotSizeEncoder, milligramsFromString)
import Models.Utils exposing (slugify)
import PageData
import Ports
import Product exposing (ProductId)
import RemoteData exposing (WebData)
import Routing exposing (AdminRoute(..), Route(..))
import Update.Utils exposing (noCommand)
import Views.Admin as Admin
import Views.HorizontalForm as Form
import Views.Utils exposing (icon, routeLinkAttributes, selectImageFile)



-- LIST


type alias ListForm =
    { query : String
    , onlyActive : Bool
    }


initialListForm : ListForm
initialListForm =
    { query = ""
    , onlyActive = True
    }


type ListMsg
    = InputQuery String
    | InputOnlyActive Bool


updateListForm : ListMsg -> ListForm -> ListForm
updateListForm msg model =
    case msg of
        InputQuery val ->
            { model | query = val }

        InputOnlyActive val ->
            { model | onlyActive = val }


{-| TODO: Add edit links to table rows
-}
list : ListForm -> PageData.AdminProductListData -> List (Html ListMsg)
list listForm { products } =
    let
        activeIcon isActive =
            if isActive then
                icon "check-circle text-success"

            else
                icon "times-circle text-danger"

        renderProduct { id, name, baseSku, categories, isActive } =
            tr []
                [ td [] [ text <| String.fromInt id ]
                , td [] [ text baseSku ]
                , td [] [ text name ]
                , td [] [ text <| String.join ", " categories ]
                , td [ class "text-center" ] [ activeIcon isActive ]
                , td [] [ text "Edit" ]
                ]

        searchInput =
            div [ class "input-group mr-4" ]
                [ div [ class "input-group-prepend" ] [ span [ class "input-group-text" ] [ icon "search" ] ]
                , input
                    [ type_ "search"
                    , name "search"
                    , value listForm.query
                    , onInput InputQuery
                    , class "form-control"
                    ]
                    []
                ]

        onlyActiveInput =
            div [ class "flex-shrink-0 form-check form-check-inline" ]
                [ input
                    [ class "form-check-input"
                    , type_ "checkbox"
                    , id "onlyActive"
                    , checked listForm.onlyActive
                    , onCheck InputOnlyActive
                    ]
                    []
                , label [ class "form-check-label", for "onlyActive" ]
                    [ text "Only Active Products" ]
                ]

        filterProduct p =
            List.foldr
                (\t b ->
                    b
                        && (iContains t p.name
                                || iContains t p.baseSku
                                || iContains t (String.fromInt p.id)
                                || List.any (iContains t) p.categories
                           )
                        && (p.isActive || not listForm.onlyActive)
                )
                True
                queryTerms

        iContains s1 s2 =
            String.contains s1 (String.toLower s2)

        queryTerms =
            String.words listForm.query
                |> List.map String.toLower
    in
    [ a (class "mb-2 btn btn-primary" :: (routeLinkAttributes <| Admin ProductNew))
        [ text "New Product" ]
    , div [ class "d-flex align-items-center justify-content-between mb-2" ]
        [ searchInput, onlyActiveInput ]
    , table [ class "table table-striped table-sm" ]
        [ thead []
            [ tr [ class "text-center" ]
                [ th [] [ text "ID" ]
                , th [] [ text "SKU" ]
                , th [] [ text "Name" ]
                , th [] [ text "Category" ]
                , th [] [ text "Active" ]
                , th [] []
                ]
            ]
        , tbody [] <| List.map renderProduct <| List.filter filterProduct products
        ]
    ]



-- NEW


type alias NewForm =
    { name : String
    , slug : String
    , category : CategoryId
    , baseSku : String
    , description : String
    , variants : Array NewVariant
    , isActive : Bool
    , imageName : String
    , imageData : String
    , isOrganic : Bool
    , isHeirloom : Bool
    , isSmallGrower : Bool
    , isRegional : Bool
    , errors : Api.FormErrors
    , isSaving : Bool
    }


initialNewForm : NewForm
initialNewForm =
    { name = ""
    , slug = ""
    , category = CategoryId 0
    , baseSku = ""
    , description = ""
    , isActive = True
    , imageName = ""
    , imageData = ""
    , variants = Array.repeat 1 initialVariant
    , isOrganic = False
    , isHeirloom = False
    , isSmallGrower = False
    , isRegional = False
    , errors = Api.initialErrors
    , isSaving = False
    }


type alias NewVariant =
    { skuSuffix : String
    , price : String
    , quantity : String
    , lotSizeAmount : String
    , lotSizeSelector : LotSizeSelector
    , isActive : Bool
    , id : Maybe Int
    }


initialVariant : NewVariant
initialVariant =
    { skuSuffix = ""
    , price = ""
    , quantity = ""
    , lotSizeAmount = ""
    , lotSizeSelector = LSMass
    , isActive = True
    , id = Nothing
    }


type LotSizeSelector
    = LSMass
    | LSBulbs
    | LSSlips
    | LSPlugs
    | LSCustom


type NewMsg
    = InputName String
    | InputSlug String
    | SelectCategory CategoryId
    | InputBaseSku String
    | InputDescription String
    | ToggleIsActive Bool
    | ToggleOrganic Bool
    | ToggleHeirloom Bool
    | ToggleSmallGrower Bool
    | ToggleRegional Bool
    | SelectImage
    | ImageUploaded File
    | ImageEncoded String
    | UpdateVariant Int VariantMsg
    | AddVariant
    | RemoveVariant Int
    | Submit
    | SubmitResponse (WebData (Result Api.FormErrors ProductId))


updateNewForm : NewMsg -> NewForm -> ( NewForm, Cmd NewMsg )
updateNewForm msg model =
    case msg of
        InputName val ->
            noCommand <|
                if slugify model.name == model.slug then
                    { model | name = val, slug = slugify val }

                else
                    { model | name = val }

        InputSlug val ->
            noCommand { model | slug = val }

        SelectCategory val ->
            noCommand { model | category = val }

        InputBaseSku val ->
            noCommand { model | baseSku = val }

        InputDescription val ->
            noCommand { model | description = val }

        ToggleIsActive val ->
            noCommand { model | isActive = val }

        ToggleOrganic val ->
            noCommand { model | isOrganic = val }

        ToggleHeirloom val ->
            noCommand { model | isHeirloom = val }

        ToggleSmallGrower val ->
            noCommand { model | isSmallGrower = val }

        ToggleRegional val ->
            noCommand { model | isRegional = val }

        SelectImage ->
            ( model, selectImageFile ImageUploaded )

        ImageUploaded imageFile ->
            ( { model | imageName = File.name imageFile }
            , Admin.encodeImageData ImageEncoded imageFile
            )

        ImageEncoded imageData ->
            noCommand { model | imageData = imageData }

        UpdateVariant index subMsg ->
            noCommand
                { model
                    | variants =
                        updateArray index (updateVariant subMsg) model.variants
                }

        AddVariant ->
            noCommand
                { model | variants = Array.push initialVariant model.variants }

        RemoveVariant index ->
            noCommand
                { model
                    | variants =
                        removeIndex index model.variants
                }

        Submit ->
            case validateForm model of
                Ok validVariants ->
                    let
                        jsonBody =
                            Encode.object
                                [ ( "name", Encode.string model.name )
                                , ( "slug", Encode.string model.slug )
                                , ( "category", Category.idEncoder model.category )
                                , ( "baseSku", Encode.string model.baseSku )
                                , ( "longDescription", Encode.string model.description )
                                , ( "isActive", Encode.bool model.isActive )
                                , ( "imageName", Encode.string model.imageName )
                                , ( "imageData", Encode.string model.imageData )
                                , ( "seedAttributes", encodedSeedAttribues )
                                , ( "variants", Encode.list variantEncoder validVariants )
                                ]

                        encodedSeedAttribues =
                            if List.all ((==) True) [ model.isOrganic, model.isHeirloom, model.isRegional, model.isSmallGrower ] then
                                Encode.null

                            else
                                Encode.object
                                    [ ( "organic", Encode.bool model.isOrganic )
                                    , ( "heirloom", Encode.bool model.isHeirloom )
                                    , ( "regional", Encode.bool model.isRegional )
                                    , ( "smallGrower", Encode.bool model.isSmallGrower )
                                    ]

                        variantEncoder variant =
                            Encode.object
                                [ ( "skuSuffix", Encode.string variant.skuSuffix )
                                , ( "price", centsEncoder variant.price )
                                , ( "quantity", Encode.int variant.quantity )
                                , ( "lotSize", lotSizeEncoder variant.lotSize )
                                , ( "isActive", Encode.bool variant.isActive )
                                ]
                    in
                    ( { model | isSaving = True }
                    , Api.post Api.AdminNewProduct
                        |> Api.withJsonBody jsonBody
                        |> Api.withErrorHandler Product.idDecoder
                        |> Api.sendRequest SubmitResponse
                    )

                Err errors ->
                    ( { model | errors = errors }
                    , Ports.scrollToErrorMessage
                    )

        SubmitResponse response ->
            case response of
                RemoteData.Success (Ok _) ->
                    -- TODO: Redirect to ProductEdit page
                    ( { model | isSaving = False }, Cmd.none )

                RemoteData.Success (Err errors) ->
                    ( { model | errors = errors, isSaving = False }
                    , Ports.scrollToErrorMessage
                    )

                RemoteData.Failure error ->
                    ( { model | errors = Api.apiFailureToError error, isSaving = False }
                    , Ports.scrollToErrorMessage
                    )

                _ ->
                    noCommand { model | isSaving = False }


type VariantMsg
    = InputSkuSuffix String
    | InputPrice String
    | InputQuantity String
    | InputLotSizeAmount String
    | SelectLotSizeSelector LotSizeSelector
    | ToggleVariantIsActive Bool


updateVariant : VariantMsg -> NewVariant -> NewVariant
updateVariant msg model =
    case msg of
        InputSkuSuffix val ->
            { model | skuSuffix = String.toUpper val }

        InputPrice val ->
            { model | price = val }

        InputQuantity val ->
            { model | quantity = val }

        InputLotSizeAmount val ->
            { model | lotSizeAmount = val }

        SelectLotSizeSelector val ->
            { model | lotSizeSelector = val }

        ToggleVariantIsActive val ->
            { model | isActive = val }


type alias ValidVariant =
    { skuSuffix : String
    , price : Cents
    , quantity : Int
    , lotSize : LotSize
    , isActive : Bool
    , id : Maybe Int
    }


validateForm : NewForm -> Result Api.FormErrors (List ValidVariant)
validateForm model =
    let
        validateVariant index variant =
            validate index
                variant
                (fromMaybe "Enter a valid dollar amount." <| centsFromString variant.price)
                (validateInt identity variant.quantity)
                (validateLotSize variant)

        validateLotSize { lotSizeSelector, lotSizeAmount } =
            case lotSizeSelector of
                LSCustom ->
                    Ok <| CustomLotSize lotSizeAmount

                LSMass ->
                    milligramsFromString lotSizeAmount
                        |> Maybe.map (Ok << Mass)
                        |> Maybe.withDefault (Err "Enter a valid decimal number.")

                LSBulbs ->
                    validateInt Bulbs lotSizeAmount

                LSSlips ->
                    validateInt Slips lotSizeAmount

                LSPlugs ->
                    validateInt Plugs lotSizeAmount

        validateInt wrapper v =
            fromMaybe "Enter a whole number." <| Maybe.map wrapper <| String.toInt v

        fromMaybe msg v =
            Maybe.map Ok v
                |> Maybe.withDefault (Err msg)
    in
    mergeValidations <| Array.indexedMap validateVariant model.variants


validate : Int -> NewVariant -> Result String Cents -> Result String Int -> Result String LotSize -> Result Api.FormErrors ValidVariant
validate index variant rPrice rQuantity rSize =
    let
        apply : String -> Result String a -> Result Api.FormErrors (a -> b) -> Result Api.FormErrors b
        apply fieldName validation result =
            let
                errorField =
                    "variant-" ++ String.fromInt index ++ "-" ++ fieldName
            in
            case ( validation, result ) of
                ( Err msg, Err r ) ->
                    Err <|
                        Api.addError errorField msg r

                ( Err msg, Ok _ ) ->
                    Err <| Api.addError errorField msg Api.initialErrors

                ( Ok _, Err r ) ->
                    Err r

                ( Ok a, Ok aToB ) ->
                    Ok <| aToB a

        constructor c q l =
            { skuSuffix = variant.skuSuffix
            , isActive = variant.isActive
            , id = variant.id
            , price = c
            , quantity = q
            , lotSize = l
            }
    in
    Result.Ok constructor
        |> apply "price" rPrice
        |> apply "quantity" rQuantity
        |> apply "lotSize" rSize


mergeValidations : Array (Result Api.FormErrors a) -> Result Api.FormErrors (List a)
mergeValidations =
    let
        merge :
            Result Api.FormErrors a
            -> Result Api.FormErrors (List a)
            -> Result Api.FormErrors (List a)
        merge validation currentResult =
            case ( validation, currentResult ) of
                ( Err e1, Err e2 ) ->
                    Err <|
                        Dict.merge
                            Dict.insert
                            (\f l r errs -> Dict.insert f (l ++ r) errs)
                            Dict.insert
                            e1
                            e2
                            Dict.empty

                ( Ok _, Err _ ) ->
                    currentResult

                ( Err e, Ok _ ) ->
                    Err e

                ( Ok v1, Ok vs ) ->
                    Ok <| v1 :: vs
    in
    Array.foldr merge (Ok [])


new : NewForm -> PageData.AdminNewProductData -> List (Html NewMsg)
new model { categories } =
    let
        inputRow s =
            Form.inputRow model.errors (s model)

        renderCategoryOption { id, name } =
            option
                [ value <| (\(CategoryId i) -> String.fromInt i) id
                , selected <| id == model.category
                ]
                [ text name ]

        blankOption =
            if model.category == CategoryId 0 then
                [ option [ value "", selected True ] [ text "" ] ]

            else
                []
    in
    [ form [ class <| Admin.formSavingClass model, onSubmit Submit ]
        [ Form.genericErrorText <| not <| Dict.isEmpty model.errors
        , Api.generalFormErrors model
        , h3 [] [ text "Base Product" ]
        , inputRow .name InputName True "Name" "name" "text" "off"
        , inputRow .slug InputSlug True "Slug" "slug" "text" "off"
        , Form.selectRow Category.idParser SelectCategory "Category" True <|
            blankOption
                ++ List.map renderCategoryOption categories
        , inputRow .baseSku InputBaseSku True "Base SKU" "baseSku" "text" "off"
        , Form.textareaRow model.errors model.description InputDescription False "Description" "description" 10
        , Form.checkboxRow model.isActive ToggleIsActive "Is Enabled" "isEnabled"
        , Form.checkboxRow model.isOrganic ToggleOrganic "Is Organic" "isOrganic"
        , Form.checkboxRow model.isHeirloom ToggleHeirloom "Is Heirloom" "isHeirloom"
        , Form.checkboxRow model.isSmallGrower ToggleSmallGrower "Is Small Grower" "isSmallGrower"
        , Form.checkboxRow model.isRegional ToggleRegional "Is SouthEast" "isSouthEast"
        , Admin.imageSelectRow model.imageName model.imageData SelectImage "Image"
        , h3 [] [ text "Variants" ]
        , div [] <|
            List.intersperse (hr [] []) <|
                Array.toList <|
                    Array.indexedMap (variantForm model.errors) model.variants
        , div [ class "form-group mb-4" ]
            [ Admin.submitOrSavingButton model "Add Product"
            , button
                [ class "ml-3 btn btn-secondary"
                , type_ "button"
                , onClick AddVariant
                ]
                [ text "Add Variant" ]
            ]
        ]
    ]


variantForm : Api.FormErrors -> Int -> NewVariant -> Html NewMsg
variantForm errors index variant =
    let
        fieldName n =
            "variant-" ++ String.fromInt index ++ "-" ++ n

        variantInput s m r l n t =
            Form.inputRow errors
                (s variant)
                (UpdateVariant index << m)
                r
                l
                (fieldName n)
                t
                "off"

        removeButton =
            if variant.id == Nothing then
                div [ class "text-right form-group" ]
                    [ button
                        [ class "btn btn-danger"
                        , type_ "button"
                        , onClick <| RemoveVariant index
                        ]
                        [ text "Remove Variant" ]
                    ]

            else
                text ""
    in
    fieldset [ class "form-group" ]
        [ variantInput .skuSuffix InputSkuSuffix False "SKU Suffix" "skuSuffix" "text"
        , variantInput .price InputPrice True "Price" "price" "text"
        , variantInput .quantity InputQuantity True "Quantity" "quantity" "number"
        , lotSizeRow errors index variant.lotSizeSelector variant.lotSizeAmount
        , Form.checkboxRow variant.isActive
            (UpdateVariant index << ToggleVariantIsActive)
            "Is Enabled"
            (fieldName "isEnabled")
        , removeButton
        ]


lotSizeRow : Api.FormErrors -> Int -> LotSizeSelector -> String -> Html NewMsg
lotSizeRow errors index selectedType enteredAmount =
    let
        fieldErrors =
            Dict.get ("variant-" ++ String.fromInt index ++ "-lotsize") errors
                |> Maybe.withDefault []

        errorHtml =
            if List.isEmpty fieldErrors then
                text ""

            else
                fieldErrors
                    |> List.map text
                    |> List.intersperse (br [] [])
                    |> div [ class "invalid-feedback" ]

        amountId =
            "LotSizeAmount"

        inputAttrs =
            case selectedType of
                LSCustom ->
                    [ type_ "text" ]

                LSMass ->
                    [ type_ "number", A.min "0.001", step "0.001" ]

                _ ->
                    [ type_ "number", A.min "1", step "1" ]

        selectId =
            "LotSizeSelector"

        onSelect =
            targetValue
                |> Decode.andThen sizeDecoder
                |> Decode.map (UpdateVariant index << SelectLotSizeSelector)
                |> on "change"

        sizeToValue size =
            case size of
                LSCustom ->
                    "custom"

                LSMass ->
                    "mass"

                LSBulbs ->
                    "bulbs"

                LSSlips ->
                    "slips"

                LSPlugs ->
                    "plugs"

        sizeToString size =
            case size of
                LSCustom ->
                    "Custom"

                LSMass ->
                    "Mass (g)"

                LSBulbs ->
                    "Bulbs"

                LSSlips ->
                    "Slips"

                LSPlugs ->
                    "Plugs"

        sizeDecoder str =
            case str of
                "custom" ->
                    Decode.succeed LSCustom

                "mass" ->
                    Decode.succeed LSMass

                "bulbs" ->
                    Decode.succeed LSBulbs

                "slips" ->
                    Decode.succeed LSSlips

                "plugs" ->
                    Decode.succeed LSPlugs

                _ ->
                    Decode.fail <| "Unrecognized lot size type: " ++ str

        options =
            [ LSMass, LSBulbs, LSSlips, LSPlugs, LSCustom ]
                |> List.map
                    (\t ->
                        option [ value <| sizeToValue t ] [ text <| sizeToString t ]
                    )
    in
    Form.withLabel "Lot Size"
        True
        [ input
            ([ id <| "input" ++ amountId
             , name amountId
             , required True
             , value enteredAmount
             , onInput (UpdateVariant index << InputLotSizeAmount)
             , class "form-control w-50 d-inline-block"
             ]
                ++ inputAttrs
            )
            []
        , select
            [ id <| "input" ++ selectId
            , name selectId
            , onSelect
            , class "form-control w-25 d-inline-block ml-4"
            ]
            options
        , errorHtml
        ]



-- UTILS


updateArray : Int -> (a -> a) -> Array a -> Array a
updateArray index updater arr =
    Array.get index arr
        |> Maybe.map (\v -> Array.set index (updater v) arr)
        |> Maybe.withDefault arr


removeIndex : Int -> Array a -> Array a
removeIndex index arr =
    Array.append
        (Array.slice 0 index arr)
        (Array.slice (index + 1) (Array.length arr) arr)
