module SiteUI.Breadcrumbs exposing (view)

import Html exposing (Html, a, li, node, ol, span, text)
import Html.Attributes exposing (class, id)
import Messages exposing (Msg(..))
import PageData exposing (PageData)
import Paginate
import Products.Pagination as Pagination
import RemoteData
import Routing exposing (AdminRoute(..), Route(..))
import Views.Aria as Aria
import Views.Microdata as Microdata
import Views.Utils exposing (routeLinkAttributes)


view : Route -> PageData -> Html Msg
view route pageData =
    let
        items =
            if List.isEmpty childItems then
                [ activeItem "Home" 1 ]

            else
                List.indexedMap (\i f -> f <| i + 1) <|
                    inactiveItem "Home" Routing.homePage
                        :: childItems

        activeItem content position =
            li (class "breadcrumb-item active" :: Microdata.itemListElement)
                [ span [ Microdata.name ] [ text content ]
                , Microdata.positionMeta position
                ]

        inactiveItem content itemRoute position =
            li (class "breadcrumb-item" :: Microdata.itemListElement)
                [ a (Microdata.item :: routeLinkAttributes itemRoute)
                    [ span [ Microdata.name ] [ text content ]
                    ]
                , Microdata.positionMeta position
                ]

        childItems =
            case route of
                PageDetails "home" _ ->
                    []

                PageDetails _ _ ->
                    pageData.pageDetails
                        |> RemoteData.toMaybe
                        |> maybeToList (.name >> activeItem >> List.singleton)

                CategoryDetails _ _ ->
                    Paginate.getResponseData pageData.categoryDetails
                        |> maybeToList categoryDetailsToBreadcrumbs

                ProductDetails _ _ ->
                    pageData.productDetails
                        |> RemoteData.toMaybe
                        |> maybeToList productDetailsToBreadcrumbs

                AdvancedSearch ->
                    singleItem "Advanced Search"

                SearchResults _ _ ->
                    singleItem "Search Results"

                CreateAccount ->
                    singleItem "Create an Account"

                CreateAccountSuccess ->
                    [ inactiveItem "Create An Account" CreateAccount
                    , activeItem "Success"
                    ]

                Login _ ->
                    singleItem "Login"

                ResetPassword Nothing ->
                    [ inactiveItem "Login" <| Login Nothing
                    , activeItem "Reset Password"
                    ]

                ResetPassword (Just _) ->
                    [ inactiveItem "Login" <| Login Nothing
                    , activeItem "Change Password"
                    ]

                MyAccount ->
                    singleItem "My Account"

                EditLogin ->
                    [ inactiveItem "My Account" MyAccount
                    , activeItem "Edit Login Details"
                    ]

                EditAddress ->
                    [ inactiveItem "My Account" MyAccount
                    , activeItem "Edit Addresses"
                    ]

                OrderDetails orderId ->
                    [ inactiveItem "My Account" MyAccount
                    , activeItem <| "Order #" ++ String.fromInt orderId
                    ]

                Cart ->
                    singleItem "Shopping Cart"

                QuickOrder ->
                    singleItem "Quick Order"

                Checkout ->
                    singleItem "Checkout"

                CheckoutSuccess _ _ ->
                    singleItem "Order Complete"

                Admin Dashboard ->
                    singleItem "Dashboard"

                Admin CategoryList ->
                    singleItem "Categories"

                Admin CategoryNew ->
                    [ inactiveItem "Categories" (Admin CategoryList)
                    , activeItem "New Category"
                    ]

                Admin (CategoryEdit _) ->
                    [ inactiveItem "Categories" (Admin CategoryList)
                    , activeItem "Edit Category"
                    ]

                Admin PageList ->
                    singleItem "Pages"

                Admin PageNew ->
                    [ inactiveItem "Pages" (Admin PageList)
                    , activeItem "New Page"
                    ]

                Admin (PageEdit _) ->
                    [ inactiveItem "Pages" (Admin PageList)
                    , activeItem "Edit Page"
                    ]

                Admin (OrderList _) ->
                    singleItem "Orders"

                Admin (AdminOrderDetails orderId) ->
                    [ inactiveItem "Orders"
                        (Admin <| OrderList { page = 1, perPage = 50, query = "" })
                    , activeItem <| "Order #" ++ String.fromInt orderId
                    ]

                Admin (CustomerList _) ->
                    singleItem "Customers"

                Admin (CustomerEdit _) ->
                    [ inactiveItem "Customers"
                        (Admin <| CustomerList { page = 1, perPage = 50, query = "" })
                    , activeItem "Edit Customer"
                    ]

                Admin ProductList ->
                    singleItem "Products"

                Admin ProductNew ->
                    [ inactiveItem "Products" <| Admin ProductList
                    , activeItem "New"
                    ]

                Admin (ProductEdit _) ->
                    [ inactiveItem "Products" <| Admin ProductList
                    , activeItem "Edit Product"
                    ]

                Admin CouponList ->
                    singleItem "Coupons"

                Admin CouponNew ->
                    [ inactiveItem "Coupons" <| Admin CouponList
                    , activeItem "New Coupon"
                    ]

                Admin (CouponEdit _) ->
                    [ inactiveItem "Coupons" <| Admin CouponList
                    , activeItem "Edit Coupon"
                    ]

                Admin Surcharges ->
                    singleItem "Surcharges"

                Admin ShippingMethods ->
                    singleItem "Shipping Methods"

                Admin Settings ->
                    singleItem "Settings"

                Admin ProductSaleList ->
                    singleItem "Product Sales"

                Admin ProductSaleNew ->
                    [ inactiveItem "Product Sales" <| Admin ProductSaleList
                    , activeItem "New Sale"
                    ]

                Admin (ProductSaleEdit _) ->
                    [ inactiveItem "Product Sales" <| Admin ProductSaleList
                    , activeItem "Edit Sale"
                    ]

                Admin CategorySaleList ->
                    singleItem "Category Sales"

                Admin CategorySaleNew ->
                    [ inactiveItem "Category Sales" <| Admin CategorySaleList
                    , activeItem "New Sale"
                    ]

                Admin (CategorySaleEdit _) ->
                    [ inactiveItem "Category Sales" <| Admin CategorySaleList
                    , activeItem "Edit Sale"
                    ]

                Redirect _ ->
                    singleItem "Redirecting..."

                NotFound ->
                    singleItem "Page Not Found"

        categoryDetailsToBreadcrumbs { category, predecessors } =
            List.map predecessorCategoryToInactiveItem predecessors
                ++ [ activeItem category.name ]

        productDetailsToBreadcrumbs { product, predecessors } =
            List.map predecessorCategoryToInactiveItem predecessors
                ++ [ activeItem product.name ]

        singleItem content =
            [ activeItem content ]

        predecessorCategoryToInactiveItem { name, slug } =
            inactiveItem name (CategoryDetails slug Pagination.default)

        maybeToList f =
            Maybe.map f >> Maybe.withDefault []
    in
    node "nav"
        [ id "breadcrumbs", class "container d-print-none", Aria.label "breadcrumb" ]
        [ ol (class "breadcrumb mb-0" :: Microdata.breadcrumbList) items ]
