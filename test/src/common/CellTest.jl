function test_cell()
@testset "Cell" begin

a = Cell(1)
b = Cell(2)
@test a[] == 1
@test b[] == 2
@test isuptodate(a)
@test isuptodate(b)

# computed cell
c = Cell(() -> a[] + b[])
@test !isuptodate(c)
@test c[] == 3
@test isuptodate(c)

# mutation invalidates dependents
a[] = 10
@test isuptodate(a)
@test !isuptodate(c)
@test c[] == 12

# deep chain
d = Cell(() -> c[] * 2)
@test d[] == 24
b[] = 3
@test !isuptodate(c)
@test !isuptodate(d)
@test d[] == 26  # (10+3)*2

# switch computed → primitive
c[] = 99
@test c[] == 99
@test isuptodate(c)
a[] = 50
@test isuptodate(c)  # no longer depends on a
@test c[] == 99

# switch primitive → computed
setfn!(c, () -> a[] * b[])
@test !isuptodate(c)
@test c[] == 150  # 50*3

# re-tracking after setfn!
a[] = 2
@test !isuptodate(c)
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
@test isuptodate(cond)  # cond should still be valid

end # @testset "Cell"
end # test_cell
