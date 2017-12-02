-module(steady_vector).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-compile(
   [{no_auto_import,[{size,1}]},
    {inline, [{tail_start,1},
              {tuple_append,2},
              {tuple_foreach,2},
              {tuple_delete,2},
              {tuple_delete_last,1},
              {tuple_foldl,3},
              {tuple_foldl_recur,5},
              {tuple_foldr,3},
              {tuple_foldr_recur,5},
              {tuple_foreach_recur,4},
              {tuple_map,2},
              {tuple_map_recur,5},
              {tuple_get,2},
              {tuple_set,3}]}
   ]).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([append/2]).                -ignore_xref({append,2}).
-export([get/2]).                   -ignore_xref({get,2}).
-export([get/3]).                   -ignore_xref({get,3}).
-export([filter/2]).                -ignore_xref({filter,2}).
-export([find/2]).                  -ignore_xref({find,2}).
-export([foldl/3]).                 -ignore_xref({foldl,3}).
-export([foldr/3]).                 -ignore_xref({foldr,3}).
-export([foreach/2]).               -ignore_xref({foreach,2}).
-export([from_list/1]).             -ignore_xref({from_list,1}).
-export([is_empty/1]).              -ignore_xref({is_empty,1}).
-export([is_steady_vector/1]).      -ignore_xref({is_steady_vector,1}).
-export([last/1]).                  -ignore_xref({last,1}).
-export([last/2]).                  -ignore_xref({last,2}).
-export([map/2]).                   -ignore_xref({map,2}).
-export([new/0]).                   -ignore_xref({new,0}).
-export([remove_last/1]).           -ignore_xref({remove_last,1}).
-export([set/3]).                   -ignore_xref({set,3}).
-export([size/1]).                  -ignore_xref({size,1}).
-export([to_list/1]).               -ignore_xref({to_list,1}).

%% ------------------------------------------------------------------
%% Macro Definitions
%% ------------------------------------------------------------------

-ifdef(TEST).
-define(shift, 2).
-else.
-define(shift, 5).
-endif.

-define(block_size, (1 bsl ?shift)).
-define(mask, (?block_size - 1)).

-define(is_index(I), (is_integer((I)) andalso (I) >= 0)).
-define(is_existing_index(I, V), (?is_index((I)) andalso (I) < (V)#steady_vector.count)).
-define(is_next_index(I, V), ((I) =:= (V)#steady_vector.count)).
-define(is_vector(V), (is_record(V, steady_vector))).

-define(arg_error, (error(badarg))).
-define(vec_error(Vector), (error({badvec,Vector}))).
-define(empty_vec_error, (error(emptyvec))).

%% ------------------------------------------------------------------
%% Record and Type Definitions
%% ------------------------------------------------------------------

-type shift() :: pos_integer().

-type index() :: non_neg_integer().
-export_type([index/0]).

-record(steady_vector, {
          count = 0 :: index(),
          shift = ?shift :: shift(),
          root = {} :: tuple(),
          tail = {} :: tuple()
         }).
-opaque t() :: #steady_vector{}.
-export_type([t/0]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

-spec append(Value, Vector1) -> Vector2
            when Value :: term(),
                 Vector1 :: t(),
                 Vector2 :: t().
append(Value, #steady_vector{ tail = Tail } = Vector) when tuple_size(Tail) < ?block_size ->
    Vector#steady_vector{
      count = Vector#steady_vector.count + 1,
      tail = tuple_append(Value, Tail)
     };
append(NewValue, #steady_vector{} = Vector) ->
    #steady_vector{ count = Count, shift = Shift, root = Root, tail = Tail } = Vector,
    NewCount = Count + 1,
    NewTail = {NewValue},
    case append_recur(Root, Shift, Tail) of
        {ok, NewRoot} ->
            Vector#steady_vector{ count = NewCount, root = NewRoot, tail = NewTail };
        {overflow, TailPath} ->
            NewShift = Shift + ?shift,
            NewRoot = {Root, TailPath},
            Vector#steady_vector{ count = NewCount, shift = NewShift, root = NewRoot, tail = NewTail }
    end;
append(_NewValue, Vector) ->
    ?vec_error(Vector).

-spec get(Index, Vector) -> Value | no_return()
            when Index :: index(),
                 Vector :: t(),
                 Value :: term().
get(Index, Vector) when ?is_existing_index(Index, Vector) ->
    fast_get(Index, Vector);
get(_Index, Vector) when ?is_vector(Vector) ->
    ?arg_error;
get(_Index, Vector) ->
    ?vec_error(Vector).

-spec get(Index, Vector, Default) -> Value | Default
            when Index :: index(),
                 Vector :: t(),
                 Default :: term(),
                 Value :: term().
get(Index, Vector, Default) when ?is_index(Index), ?is_vector(Vector) ->
    case Index < Vector#steady_vector.count of
        true -> fast_get(Index, Vector);
        _ -> Default
    end;
get(_Index, Vector, _Default) when ?is_vector(Vector) ->
    ?arg_error;
get(_Index, Vector, _Default) ->
    ?vec_error(Vector).

-spec filter(Fun, Vector1) -> Vector2
            when Fun :: ValueFun | PairFun,
                 ValueFun :: fun ((Value) -> boolean()),
                 PairFun :: fun((Index, Value) -> boolean()),
                 Index :: index(),
                 Value :: term(),
                 Vector1 :: t(),
                 Vector2 :: t().
filter(Fun, Vector) when is_function(Fun, 1) ->
    foldl(
      fun (Value, Acc) ->
              case Fun(Value) of
                  true -> append(Value, Acc);
                  false -> Acc
              end
      end,
      new(), Vector);
filter(Fun, Vector) when is_function(Fun, 2) ->
    foldl(
      fun (Index, Value, Acc) ->
              case Fun(Index, Value) of
                  true -> append(Value, Acc);
                  false -> Acc
              end
      end,
      new(), Vector);
filter(_Fun, Vector) when ?is_vector(Vector) ->
    ?arg_error;
filter(_Fun, Vector) ->
    ?vec_error(Vector).

-spec find(Index, Vector) -> {ok, Value} | error
            when Index :: index(),
                 Vector :: t(),
                 Value :: term().
find(Index, Vector) when ?is_index(Index), ?is_vector(Vector) ->
    case Index < Vector#steady_vector.count of
        true -> {ok, fast_get(Index, Vector)};
        _ -> error
    end;
find(_Index, Vector) when ?is_vector(Vector) ->
    ?arg_error;
find(_Index, Vector) ->
    ?vec_error(Vector).

-spec foldl(Fun, Acc0, Vector) -> AccN
            when Fun :: ValueFun | PairFun,
                 ValueFun :: fun((Value, Acc1) -> Acc2),
                 PairFun :: fun((Index, Value, Acc1) -> Acc2),
                 Index :: index(),
                 Value :: term(),
                 Acc1 :: Acc0 | Acc2,
                 Acc2 :: term() | AccN,
                 Acc0 :: term(),
                 Vector :: t(),
                 AccN :: term().
foldl(Fun, Acc0, Vector) when is_function(Fun, 2), ?is_vector(Vector) ->
    foldl_leaf_blocks(
      fun (Block, Acc) -> tuple_foldl(Fun, Acc, Block) end,
      Acc0, Vector);
foldl(Fun, Acc0, Vector) when is_function(Fun, 3), ?is_vector(Vector) ->
    TupleFoldFun =
        fun (Value, {IndexAcc, CallerAcc1}) ->
                CallerAcc2 = Fun(IndexAcc, Value, CallerAcc1),
                {IndexAcc + 1, CallerAcc2}
        end,

    LeafFoldAcc0 = {0, Acc0},
    {_Count, LeafFoldAccN} =
        foldl_leaf_blocks(
          fun (Block, LeafFoldAcc) ->
                  tuple_foldl(TupleFoldFun, LeafFoldAcc, Block)
          end,
          LeafFoldAcc0,
          Vector),
    LeafFoldAccN;
foldl(_Fun, _Acc0, Vector) when ?is_vector(Vector) ->
    ?arg_error;
foldl(_Fun, _Acc0, Vector) ->
    ?vec_error(Vector).

-spec foldr(Fun, Acc0, Vector) -> AccN
            when Fun :: ValueFun | PairFun,
                 ValueFun :: fun((Value, Acc1) -> Acc2),
                 PairFun :: fun((Index, Value, Acc1) -> Acc2),
                 Index :: index(),
                 Value :: term(),
                 Acc1 :: Acc0 | Acc2,
                 Acc2 :: term() | AccN,
                 Acc0 :: term(),
                 Vector :: t(),
                 AccN :: term().
foldr(Fun, Acc0, Vector) when is_function(Fun, 2), ?is_vector(Vector) ->
    foldr_leaf_blocks(
      fun (Block, Acc) -> tuple_foldr(Fun, Acc, Block) end,
      Acc0, Vector);
foldr(Fun, Acc0, Vector) when is_function(Fun, 3), ?is_vector(Vector) ->
    TupleFoldFun =
        fun (Value, {IndexAcc, CallerAcc1}) ->
                CallerAcc2 = Fun(IndexAcc, Value, CallerAcc1),
                {IndexAcc - 1, CallerAcc2}
        end,

    LeafFoldAcc0 = {Vector#steady_vector.count - 1, Acc0},
    {_Count, LeafFoldAccN} =
        foldr_leaf_blocks(
          fun (Block, LeafFoldAcc) ->
                  tuple_foldr(TupleFoldFun, LeafFoldAcc, Block)
          end,
          LeafFoldAcc0,
          Vector),
    LeafFoldAccN;
foldr(_Fun, _Acc0, Vector) when ?is_vector(Vector) ->
    ?arg_error;
foldr(_Fun, _Acc0, Vector) ->
    ?vec_error(Vector).

-spec foreach(Fun, Vector) -> ok
            when Fun :: ValueFun | PairFun,
                 ValueFun :: fun((Value) -> term()),
                 PairFun :: fun((Index, Value) -> term()),
                 Index :: index(),
                 Value :: term(),
                 Vector :: t().
foreach(Fun, Vector) when is_function(Fun, 1), ?is_vector(Vector) ->
    foreach_leaf_block(
      fun (Block) -> tuple_foreach(Fun, Block) end,
      Vector);
foreach(Fun, Vector) when is_function(Fun, 2) ->
    foldl(
      fun (Index, Value, ok) ->
              _ = Fun(Index, Value),
              ok
      end,
      ok, Vector);
foreach(_Fun, Vector) when ?is_vector(Vector) ->
    ?arg_error;
foreach(_Fun, Vector) ->
    ?vec_error(Vector).

-spec from_list(List) -> Vector
            when List :: list(),
                 Vector :: t().
from_list(List) when is_list(List) ->
    lists:foldl(fun append/2, new(), List);
from_list(_List) ->
    ?arg_error.

-spec is_empty(Vector) -> boolean()
            when Vector :: t().
is_empty(Vector) when ?is_vector(Vector) ->
    Vector#steady_vector.count =:= 0;
is_empty(Vector) ->
    ?vec_error(Vector).

-spec is_steady_vector(Term) -> boolean()
            when Term :: term().
is_steady_vector(Term) ->
    ?is_vector(Term).

-spec last(Vector) -> Value | no_return()
            when Vector :: t(),
                 Value :: term().
last(#steady_vector{ count = Count } = Vector) ->
    case Count > 0 of
        true -> fast_get(Count - 1, Vector);
        _ -> ?empty_vec_error(Vector)
    end;
last(Vector) ->
    ?vec_error(Vector).

-spec last(Vector, Default) -> Value | Default
            when Vector :: t(),
                 Default :: term(),
                 Value :: term().
last(#steady_vector{ count = Count } = Vector, Default) ->
    case Count > 0 of
        true -> fast_get(Count - 1, Vector);
        _ -> Default
    end;
last(Vector, _Default) ->
    ?vec_error(Vector).

-spec map(Fun, Vector1) -> Vector2
            when Fun :: ValueFun | PairFun,
                 ValueFun :: fun((Value1) -> Value2),
                 PairFun :: fun((Index, Value1) -> Value2),
                 Index :: index(),
                 Value1 :: term(),
                 Value2 :: term(),
                 Vector1 :: t(),
                 Vector2 :: t().
map(Fun, Vector) when is_function(Fun, 1), ?is_vector(Vector) ->
    map_leaf_blocks(
      fun (Block) -> tuple_map(Fun, Block) end,
      Vector);
map(Fun, Vector) when is_function(Fun, 2) ->
    foldl(
      fun (Index, Value, Acc) ->
              MappedValue = Fun(Index, Value),
              append(MappedValue, Acc)
      end,
      new(), Vector);
map(_Fun, Vector) when ?is_vector(Vector) ->
    ?arg_error;
map(_Fun, Vector) ->
    ?vec_error(Vector).

-spec new() -> Vector
            when Vector :: t().
new() ->
    #steady_vector{}.

-spec remove_last(Vector1) -> Vector2 | no_return()
            when Vector1 :: t(),
                 Vector2 :: t().
remove_last(#steady_vector{ tail = Tail } = Vector) when tuple_size(Tail) > 1 ->
    NewTail = tuple_delete_last(Tail),
    Vector#steady_vector{
      count = Vector#steady_vector.count - 1,
      tail = NewTail };
remove_last(#steady_vector{ count = Count } = Vector) when Count > 1 ->
    #steady_vector{ shift = Shift, root = Root } = Vector,
    NewCount = Count - 1,
    {NewRoot, NewTail} = remove_last_recur(Root, Shift),
    if tuple_size(NewRoot) =:= 1 andalso Shift > ?shift ->
           NewShift = Shift - ?shift,
           {InnerNewRoot} = NewRoot, % remove topmost tree level
           Vector#steady_vector{ count = NewCount, root = InnerNewRoot,
                                 shift = NewShift, tail = NewTail };
       true ->
           Vector#steady_vector{ count = NewCount, root = NewRoot, tail = NewTail }
    end;
remove_last(#steady_vector{ count = 1 }) ->
    new();
remove_last(Vector) ->
    ?vec_error(Vector).

-spec set(Index, Value, Vector1) -> Vector2 | no_return()
            when Index :: index(),
                 Value :: term(),
                 Vector1 :: t(),
                 Vector2 :: t().
set(Index, Value, Vector) when ?is_existing_index(Index, Vector) ->
    case Index >= tail_start(Vector) of
        true ->
            Tail = Vector#steady_vector.tail,
            ValueIndex = Index band ?mask,
            NewTail = tuple_set(ValueIndex, Value, Tail),
            Vector#steady_vector{ tail = NewTail };
        _ ->
            Root = Vector#steady_vector.root,
            NewRoot = set_recur(Root, Vector#steady_vector.shift, Index, Value),
            Vector#steady_vector{ root = NewRoot }
    end;
set(Index, Value, Vector) when ?is_next_index(Index, Vector) ->
    append(Value, Vector);
set(_Index, _Value, Vector) when ?is_vector(Vector) ->
    ?arg_error;
set(_Index, _Value, Vector) ->
    ?vec_error(Vector).

-spec size(Vector) -> non_neg_integer()
            when Vector :: t().
size(#steady_vector{ count = Count }) ->
    Count;
size(Vector) ->
    ?vec_error(Vector).

-spec to_list(Vector) -> list()
            when Vector :: t().
to_list(Vector) ->
    foldr_leaf_blocks(
      fun (Block, Acc) ->
              tuple_to_list(Block) ++ Acc
      end,
      [], Vector).

%% ------------------------------------------------------------------
%% Internal Function Definitions - Appending
%% ------------------------------------------------------------------

append_recur(Node, Level, Tail) when Level > ?shift ->
    LastChildIndex = tuple_size(Node) - 1,
    LastChild = tuple_get(LastChildIndex, Node),
    case append_recur(LastChild, Level - ?shift, Tail) of
        {ok, NewChild} ->
            {ok, tuple_set(LastChildIndex, NewChild, Node)};
        {overflow, TailPath} ->
            append_here(Node, TailPath)
    end;
append_recur(Node, _Level, Tail) ->
    append_here(Node, Tail).

append_here(Node, TailPath) ->
    case tuple_size(Node) < ?block_size of
        true ->
            {ok, tuple_append(TailPath, Node)};
        _ ->
            {overflow, {TailPath}}
    end.

%% ------------------------------------------------------------------
%% Internal Function Definitions - Fetching
%% ------------------------------------------------------------------

fast_get(Index, Vector) ->
    ValueIndex = Index band ?mask,
    case Index >= tail_start(Vector) of
        true ->
            tuple_get(ValueIndex, Vector#steady_vector.tail);
        _ ->
            Node = get_recur(Vector#steady_vector.root, Vector#steady_vector.shift, Index),
            tuple_get(ValueIndex, Node)
    end.

get_recur(Node, Level, Index) when Level > 0 ->
    ChildIndex = (Index bsr Level) band ?mask,
    Child = tuple_get(ChildIndex, Node),
    get_recur(Child, Level - ?shift, Index);
get_recur(Leaf, _Level, _Index) ->
    Leaf.

%% ------------------------------------------------------------------
%% Internal Function Definitions - Folding Left
%% ------------------------------------------------------------------

foldl_leaf_blocks(Fun, Acc1, Vector) ->
    #steady_vector{ shift = Shift, root = Root, tail = Tail } = Vector,
    Acc2 = foldl_descendant_leaf_blocks(Fun, Acc1, Root, Shift),
    Fun(Tail, Acc2).

foldl_descendant_leaf_blocks(Fun, Acc0, ParentNode, Level) ->
    ChildrenLevel = Level - ?shift,
    tuple_foldl(
      fun (Child, Acc) ->
              foldl_node_leaf_blocks(Fun, Acc, Child, ChildrenLevel)
      end,
      Acc0, ParentNode).

foldl_node_leaf_blocks(Fun, Acc, Node, Level) when Level > 0 ->
    foldl_descendant_leaf_blocks(Fun, Acc, Node, Level);
foldl_node_leaf_blocks(Fun, Acc, Node, _Level) ->
    Fun(Node, Acc).

%% ------------------------------------------------------------------
%% Internal Function Definitions - Folding Right
%% ------------------------------------------------------------------

foldr_leaf_blocks(Fun, Acc1, Vector) ->
    #steady_vector{ shift = Shift, root = Root, tail = Tail } = Vector,
    Acc2 = Fun(Tail, Acc1),
    foldr_descendant_leaf_blocks(Fun, Acc2, Root, Shift).

foldr_descendant_leaf_blocks(Fun, Acc0, ParentNode, Level) ->
    ChildrenLevel = Level - ?shift,
    tuple_foldr(
      fun (Child, Acc) ->
              foldr_node_leaf_blocks(Fun, Acc, Child, ChildrenLevel)
      end,
      Acc0, ParentNode).

foldr_node_leaf_blocks(Fun, Acc, Node, Level) when Level > 0 ->
    foldr_descendant_leaf_blocks(Fun, Acc, Node, Level);
foldr_node_leaf_blocks(Fun, Acc, Node, _Level) ->
    Fun(Node, Acc).

%% ------------------------------------------------------------------
%% Internal Function Definitions - Iterating
%% ------------------------------------------------------------------

foreach_leaf_block(Fun, Vector) ->
    #steady_vector{ shift = Shift, root = Root, tail = Tail } = Vector,
    foreach_descendant_leaf_block(Fun, Root, Shift),
    _ = Fun(Tail),
    ok.

foreach_descendant_leaf_block(Fun, Node, Level) ->
    ChildrenLevel = Level - ?shift,
    tuple_foreach(
      fun (ChildNode) ->
              foreach_node_leaf_block(Fun, ChildNode, ChildrenLevel)
      end,
      Node).

foreach_node_leaf_block(Fun, Node, Level) when Level > 0 ->
    foreach_descendant_leaf_block(Fun, Node, Level);
foreach_node_leaf_block(Fun, Block, _Level) ->
    Fun(Block).

%% ------------------------------------------------------------------
%% Internal Function Definitions - Mapping
%% ------------------------------------------------------------------

map_leaf_blocks(Fun, Vector) ->
    #steady_vector{ shift = Shift, root = Root, tail = Tail } = Vector,
    MappedTail = Fun(Tail),
    MappedRoot = map_descendant_leaf_blocks(Fun, Root, Shift),
    Vector#steady_vector{ root = MappedRoot, tail = MappedTail }.

map_descendant_leaf_blocks(Fun, Node, Level) ->
    ChildrenLevel = Level - ?shift,
    tuple_map(
      fun (ChildNode) ->
              map_node_leaf_blocks(Fun, ChildNode, ChildrenLevel)
      end,
      Node).

map_node_leaf_blocks(Fun, Node, Level) when Level > 0 ->
    map_descendant_leaf_blocks(Fun, Node, Level);
map_node_leaf_blocks(Fun, Block, _Level) ->
    Fun(Block).

%% ------------------------------------------------------------------
%% Internal Function Definitions - Removing
%% ------------------------------------------------------------------

remove_last_recur(Node, Level) when Level > ?shift ->
    ChildIndex = tuple_size(Node) - 1,
    Child = tuple_get(ChildIndex, Node),
    case remove_last_recur(Child, Level - ?shift) of
        {{}, LastBlock} ->
            NewNode = tuple_delete(ChildIndex, Node),
            {NewNode, LastBlock};
        {NewChild, LastBlock} ->
            NewNode = tuple_set(ChildIndex, NewChild, Node),
            {NewNode, LastBlock}
    end;
remove_last_recur(Node, _Level) ->
    ChildIndex = tuple_size(Node) - 1,
    Child = tuple_get(ChildIndex, Node),
    NewNode = tuple_delete(ChildIndex, Node),
    {NewNode, Child}.

%% ------------------------------------------------------------------
%% Internal Function Definitions - Setting
%% ------------------------------------------------------------------

set_recur(Node, Level, Index, Val) when Level > 0 ->
    ChildIndex = (Index bsr Level) band ?mask,
    Child = tuple_get(ChildIndex, Node),
    NewChild = set_recur(Child, Level - ?shift, Index, Val),
    tuple_set(ChildIndex, NewChild, Node);
set_recur(Leaf, _Level, Index, Val) ->
    ValueIndex = Index band ?mask,
    tuple_set(ValueIndex, Val, Leaf).

%% ------------------------------------------------------------------
%% Internal Function Definitions - Utilities
%% ------------------------------------------------------------------

tail_start(#steady_vector{} = Vector) ->
    Vector#steady_vector.count - tuple_size(Vector#steady_vector.tail).

tuple_append(Value, Tuple) ->
    erlang:append_element(Tuple, Value).

tuple_delete(Index, Tuple) ->
    erlang:delete_element(Index + 1, Tuple).

tuple_delete_last(Tuple) ->
    erlang:delete_element(tuple_size(Tuple), Tuple).

tuple_foldl(Fun, Acc0, Tuple) ->
    tuple_foldl_recur(Fun, Acc0, Tuple, 1, tuple_size(Tuple) + 1).

tuple_foldl_recur(_Fun, AccN, _Tuple, Index, Limit) when Index =:= Limit ->
    AccN;
tuple_foldl_recur(Fun, Acc1, Tuple, Index, Limit) ->
    Value = element(Index, Tuple),
    Acc2 = Fun(Value, Acc1),
    tuple_foldl_recur(Fun, Acc2, Tuple, Index + 1, Limit).

tuple_foldr(Fun, Acc0, Tuple) ->
    tuple_foldr_recur(Fun, Acc0, Tuple, tuple_size(Tuple), 0).

tuple_foldr_recur(_Fun, AccN, _Tuple, Index, Limit) when Index =:= Limit ->
    AccN;
tuple_foldr_recur(Fun, Acc1, Tuple, Index, Limit) ->
    Value = element(Index, Tuple),
    Acc2 = Fun(Value, Acc1),
    tuple_foldr_recur(Fun, Acc2, Tuple, Index - 1, Limit).

tuple_foreach(Fun, Tuple) ->
    tuple_foreach_recur(Fun, Tuple, 1, tuple_size(Tuple) + 1).

tuple_foreach_recur(_Fun, _Tuple, Index, Limit) when Index =:= Limit ->
    ok;
tuple_foreach_recur(Fun, Tuple, Index, Limit) ->
    Value = element(Index, Tuple),
    _ = Fun(Value),
    tuple_foreach_recur(Fun, Tuple, Index + 1, Limit).

tuple_map(Fun, Tuple) ->
    tuple_map_recur(Fun, Tuple, tuple_size(Tuple), 0, []).

tuple_map_recur(_Fun, _Tuple, Index, Limit, Acc) when Index =:= Limit ->
    list_to_tuple(Acc);
tuple_map_recur(Fun, Tuple, Index, Limit, Acc) ->
    Value = element(Index, Tuple),
    MappedValue = Fun(Value),
    tuple_map_recur(Fun, Tuple, Index - 1, Limit, [MappedValue | Acc]).

tuple_get(Index, Tuple) ->
    element(Index + 1, Tuple).

tuple_set(Index, Value, Tuple) ->
    setelement(Index + 1, Tuple, Value).

%% ------------------------------------------------------------------
%% EUnit Definitions
%% ------------------------------------------------------------------
-ifdef(TEST).

empty_test() ->
    Vec = ?MODULE:new(),
    ?assert(?MODULE:is_empty(Vec)),
    ?assertEqual(0, ?MODULE:size(Vec)),
    ?assertEqual(it_is_empty, ?MODULE:last(Vec, it_is_empty)),
    ?assertError(badarg, ?MODULE:get(0, Vec)),
    ?assertError(emptyvec, ?MODULE:last(Vec)),
    ?assertEqual(not_found, ?MODULE:get(1, Vec, not_found)),
    ?assertEqual(error, ?MODULE:find(1, Vec)).

brute_get_test() ->
    Vec = #steady_vector{ count = 5, root = {{0,1,2}, {4}} },
    ?assertEqual(0, ?MODULE:get(0, Vec)),
    ?assertEqual(1, ?MODULE:get(1, Vec)),
    ?assertEqual(2, ?MODULE:get(2, Vec)),
    ?assertEqual(4, ?MODULE:get(4, Vec)).

append_to_tail_test() ->
    Vec1 = ?MODULE:append(0, ?MODULE:new()),
    ?assertEqual(1, ?MODULE:size(Vec1)),
    ?assertNot(?MODULE:is_empty(Vec1)),
    ?assertEqual(0, ?MODULE:get(0, Vec1)),

    Vec2 = ?MODULE:append(1, Vec1),
    ?assertEqual(2, ?MODULE:size(Vec2)),
    ?assertEqual(0, ?MODULE:get(0, Vec2)),
    ?assertEqual(1, ?MODULE:get(1, Vec2)).

append_to_root_test() ->
    C = 68,
    Vec1 =
        lists:foldl(
          fun append_and_assert_element_identity/2,
          ?MODULE:new(), lists:seq(0, C - 1)),
    ?assertEqual(C, ?MODULE:size(Vec1)),

    Vec2 = assert_element_identity( ?MODULE:append(C, Vec1) ),
    ?assertEqual(C + 1, ?MODULE:size(Vec2)),
    ?assertEqual(C, ?MODULE:get(C, Vec2)),

    ?assertError(badarg, ?MODULE:get(C + 1, Vec2)),
    ?assertError(badarg, ?MODULE:get("hello", Vec2)),
    ?assertError(badarg, ?MODULE:get({1}, Vec2)).

remove_last_tail_test() ->
    Vec1 = ?MODULE:append(0, ?MODULE:new()),
    Vec1_R = ?MODULE:remove_last(Vec1),
    ?assertEqual(0, ?MODULE:size(Vec1_R)),

    Vec2 = ?MODULE:append(1, Vec1),
    Vec2_R = ?MODULE:remove_last(Vec2),
    ?assertEqual(1, ?MODULE:size(Vec2_R)),
    ?assertEqual(0, ?MODULE:get(0, Vec2_R)).

remove_last_root_test() ->
    C = 20,
    Vec1 = lists:foldl(
             fun ?MODULE:append/2,
             ?MODULE:new(), lists:seq(0, C - 1)),
    Vec2 = lists:foldl(
             fun (Index, Acc) ->
                     assert_element_identity(Acc),
                     ?assertEqual(Index + 1, ?MODULE:size(Acc)),
                     ?MODULE:remove_last(Acc)
             end,
             Vec1, lists:seq(C - 1, 0, -1)),

    ?assertEqual(0, ?MODULE:size(Vec2)),
    ?assertError({badvec,Vec2}, ?MODULE:remove_last(Vec2)).

set_tail_test() ->
    Vec1 = assert_element_identity(
             ?MODULE:set(1, 1, ?MODULE:set(0, 0, ?MODULE:new())) ),
    ?assertEqual(2, ?MODULE:size(Vec1)),

    C = 4,
    IndexSeq = lists:seq(0, C - 1),
    Vec2A = lists:foldl(
              fun ?MODULE:append/2,
              ?MODULE:new(), IndexSeq),
    Vec2B = lists:foldl(
              fun (Index, Acc) ->
                      ?MODULE:set(Index, Index + 10, Acc)
              end,
              Vec1, IndexSeq),

    ?assertEqual(?MODULE:size(Vec2A), ?MODULE:size(Vec2B)),
    lists:foreach(
      fun (Index) ->
              ?assertEqual(?MODULE:get(Index, Vec2A), ?MODULE:get(Index, Vec2B) - 10)
      end,
      IndexSeq).

set_root_test() ->
    C = 20,
    IndexSeq = lists:seq(0, C - 1),
    Vec1 = lists:foldl(
              fun ?MODULE:append/2,
              ?MODULE:new(), IndexSeq),
    Vec2 = lists:foldl(
              fun (Index, Acc) ->
                      ?MODULE:set(Index, Index + 10, Acc)
              end,
              Vec1, IndexSeq),

    ?assertEqual(?MODULE:size(Vec1), ?MODULE:size(Vec2)),
    lists:foreach(
      fun (Index) ->
              ?assertEqual(?MODULE:get(Index, Vec1), ?MODULE:get(Index, Vec2) - 10)
      end,
      IndexSeq),
    ?assertError(badarg, ?MODULE:set(1, 1, ?MODULE:new())),
    ?assertError(badarg, ?MODULE:set("bla", 1, ?MODULE:new())).

from_and_to_list_test() ->
    C = 1000,
    List = [{rand:uniform(), Index} || Index <- lists:seq(1, C)],

    % convert from
    Vec = ?MODULE:from_list(List),
    ?assertEqual(length(List), ?MODULE:size(Vec)),

    % convert to
    List2 = ?MODULE:to_list(Vec),
    ?assertEqual(?MODULE:size(Vec), length(List2)),

    % all elements were kept
    _ = lists:zipwith(
          fun (Left, Right) ->
                  ?assertEqual(Left, Right)
          end,
          List, List2).

value_filter_test() ->
    C = 1000,
    FilterFun  = fun ({V, _Index}) -> V band 1 =:= 0 end,
    List = [{rand:uniform(1000), Index} || Index <- lists:seq(1, C)],
    Vec = ?MODULE:from_list(List),
    FilteredList = lists:filter(FilterFun, List),
    FilteredVec = ?MODULE:filter(FilterFun, Vec),
    ?MODULE:foldl(
       fun (VecValue, [ListValue | Next]) ->
               ?assertEqual(VecValue, ListValue),
               Next
       end,
       FilteredList, FilteredVec).

pair_filter_test() ->
    C = 1000,
    ListFilterFun = fun ({V, _Index}) -> V band 1 =:= 0 end,
    VecFilterFun = fun (Index, {_, OrigIndex} = Value) ->
                        ?assertEqual(Index, OrigIndex - 1),
                        ListFilterFun(Value)
                   end,
    List = [{rand:uniform(1000), Index} || Index <- lists:seq(1, C)],
    Vec = ?MODULE:from_list(List),
    FilteredList = lists:filter(ListFilterFun, List),
    FilteredVec = ?MODULE:filter(VecFilterFun, Vec),
    ?MODULE:foldl(
       fun (VecValue, [ListValue | Next]) ->
               ?assertEqual(VecValue, ListValue),
               Next
       end,
       FilteredList, FilteredVec).

value_foldl_test() ->
    C = 1000,
    List = [{rand:uniform(), Index} || Index <- lists:seq(1, C)],
    Vec = ?MODULE:from_list(List),
    ?MODULE:foldl(
       fun (VecValue, [ListValue | Next]) ->
               ?assertEqual(VecValue, ListValue),
               Next
       end,
       List, Vec).

pair_foldl_test() ->
    C = 1000,
    List = [{rand:uniform(), Index} || Index <- lists:seq(1, C)],
    Vec = ?MODULE:from_list(List),
    ?MODULE:foldl(
       fun (VecIndex, {VecValue, OrigVecIndex},
            [{ListValue, OrigListIndex} | Next]) ->
               ?assertEqual(VecValue, ListValue),
               ?assertEqual(VecIndex, OrigVecIndex - 1),
               ?assertEqual(VecIndex, OrigListIndex - 1),
               Next
       end,
       List, Vec).

value_foldr_test() ->
    C = 1000,
    List = [{rand:uniform(), Index} || Index <- lists:seq(1, C)],
    Vec = ?MODULE:from_list(List),
    RevList = lists:reverse(List),
    ?MODULE:foldr(
       fun (VecValue, [ListValue | Next]) ->
               ?assertEqual(VecValue, ListValue),
               Next
       end,
       RevList, Vec).

pair_foldr_test() ->
    C = 1000,
    List = [{rand:uniform(), Index} || Index <- lists:seq(1, C)],
    Vec = ?MODULE:from_list(List),
    RevList = lists:reverse(List),
    ?MODULE:foldr(
       fun (VecIndex, {VecValue, OrigVecIndex},
            [{ListValue, OrigListIndex} | Next]) ->
               ?assertEqual(VecValue, ListValue),
               ?assertEqual(VecIndex, OrigVecIndex - 1),
               ?assertEqual(VecIndex, OrigListIndex - 1),
               Next
       end,
       RevList, Vec).

value_foreach_test() ->
    C = 1000,
    List = [{rand:uniform(), Index} || Index <- lists:seq(1, C)],
    Vec = ?MODULE:from_list(List),
    ProcDicKey = make_ref(),
    undefined = put(ProcDicKey, List),
    ?MODULE:foreach(
       fun (Value) ->
               [ListValue | Next] = get(ProcDicKey),
               ?assertEqual(Value, ListValue),
               put(ProcDicKey, Next)
       end,
       Vec),
    erlang:put(ProcDicKey, undefined).

pair_foreach_test() ->
    C = 1000,
    List = [{rand:uniform(), Index} || Index <- lists:seq(1, C)],
    Vec = ?MODULE:from_list(List),
    ProcDicKey = make_ref(),
    undefined = put(ProcDicKey, List),
    ?MODULE:foreach(
       fun (Index, {Value, OrigIndex}) ->
               [{ListValue, ListOrigIndex} | Next] = get(ProcDicKey),
               ?assertEqual(Value, ListValue),
               ?assertEqual(Index, OrigIndex - 1),
               ?assertEqual(Index, ListOrigIndex - 1),
               put(ProcDicKey, Next)
       end,
       Vec),
    erlang:put(ProcDicKey, undefined).

value_map_test() ->
    C = 1000,
    MapFun = fun ({V, Index}) -> {V * 2, Index} end,
    List = [{rand:uniform(), Index} || Index <- lists:seq(1, C)],
    Vec = ?MODULE:from_list(List),
    MappedList = lists:map(MapFun, List),
    MappedVec = ?MODULE:map(MapFun, Vec),
    ?MODULE:foldl(
       fun (VecValue, [ListValue | Next]) ->
               ?assertEqual(VecValue, ListValue),
               Next
       end,
       MappedList, MappedVec).

pair_map_test() ->
    C = 1000,
    ListMapFun = fun ({V, Index}) -> {V * 2, Index} end,
    VecMapFun = fun (Index, {_, OrigIndex} = Value) ->
                        ?assertEqual(Index, OrigIndex - 1),
                        ListMapFun(Value)
                end,
    List = [{rand:uniform(), Index} || Index <- lists:seq(1, C)],
    Vec = ?MODULE:from_list(List),
    MappedList = lists:map(ListMapFun, List),
    MappedVec = ?MODULE:map(VecMapFun, Vec),
    ?MODULE:foldl(
       fun (VecValue, [ListValue | Next]) ->
               ?assertEqual(VecValue, ListValue),
               Next
       end,
       MappedList, MappedVec).

append_and_assert_element_identity(Value, Vec1) ->
    Vec2 = ?MODULE:append(Value, Vec1),
    assert_element_identity(Vec2).

assert_element_identity(Vec) ->
    C = ?MODULE:size(Vec),

    % "randomly" use different getters
    ValidationFun =
        case C rem 3 of
            0 -> fun (Index) -> ?assertEqual(Index, ?MODULE:get(Index, Vec)) end;
            1 -> fun (Index) -> ?assertEqual(Index, ?MODULE:get(Index, Vec, not_found)) end;
            2 -> fun (Index) -> ?assertEqual({ok, Index}, ?MODULE:find(Index, Vec)) end
        end,

    lists:foreach(ValidationFun, lists:seq(0, C - 1)),

    if C > 0 ->
           ?assertEqual(C - 1, ?MODULE:last(Vec, empty)),
           ?assertEqual(C - 1, ?MODULE:last(Vec));
       true ->
           ?assertEqual(empty, ?MODULE:last(Vec, empty)),
           ?assertError(badarg, ?MODULE:last(Vec))
    end,
    Vec.

-endif.
