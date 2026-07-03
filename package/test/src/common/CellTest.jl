function test_cell()
@testset "Cell" begin

a = Cell(1)
b = Cell(2)
@test a[] == 1
@test b[] == 2
@test is_up_to_date(a)
@test is_up_to_date(b)

# computed cell
c = Cell(() -> a[] + b[])
@test !is_up_to_date(c)
@test c[] == 3
@test is_up_to_date(c)

# mutation invalidates dependents
a[] = 10
@test is_up_to_date(a)
@test !is_up_to_date(c)
@test c[] == 12

# deep chain
d = Cell(() -> c[] * 2)
@test d[] == 24
b[] = 3
@test !is_up_to_date(c)
@test !is_up_to_date(d)
@test d[] == 26  # (10+3)*2

# switch computed → primitive
c[] = 99
@test c[] == 99
@test is_up_to_date(c)
a[] = 50
@test is_up_to_date(c)  # no longer depends on a
@test c[] == 99

# switch primitive → computed
set_function!(c, () -> a[] * b[])
@test !is_up_to_date(c)
@test c[] == 150  # 50*3

# re-tracking after set_function!
a[] = 2
@test !is_up_to_date(c)
@test c[] == 6   # 2*3

# conditional dependency
flag = Cell(true)
x = Cell(10)
y = Cell(20)
cond = Cell(() -> flag[] ? x[] : y[])
@test cond[] == 10
flag[] = false
@test cond[] == 20
x[] = 999          # x is no longer a dep after last eval
@test is_up_to_date(cond)  # cond should still be valid

end # @testset "Cell"
end # test_cell
