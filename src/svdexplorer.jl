using Gadfly

@doc """Plot a given left and right singular vector and also its position in the spectrum of singular values""" ->
function svdexplorer(S::Base.LinAlg.SVD, i::Int; xu=nothing, xv=nothing)
    # Reconstruct dimensions of matrix that was SVDed
    m = size(S[:U], 1)
    n = size(S[:V], 2)
    ns= size(S[:S], 1)

    leftcolors = reverse(Color.colormap("Reds", ns+1))
    rightcolors = reverse(Color.colormap("Blues", ns+1))

    #Allow optional x axes for u or v vectors to be specified
    xu==nothing && (xu = 1:m)
    xv==nothing && (xv = 1:n)
    ubars = m < n #left vectors bars or lines? Assume we always have more data (lines) than factors (bars)
    hstack(
        #Left singular vector

            plot(x=xu, y=sub(S[:U],:,i), ubars ? Geom.bar : Geom.line,
            Theme(default_color=leftcolors[i]),
            ubars ? Coord.Cartesian(xmin=0.5, xmax=m+0.5, ymin=-1.0, ymax=1.0) : Coord.Cartesian(xmin=minimum(xu), xmax=maximum(xu)),
            Guide.xlabel("Time"), Guide.ylabel(""),
            Guide.title("U[$i]")),

        #Singular values
        plot(x=1:ns, y=S[:S], Geom.point, Geom.line,
            xintercept = [i], Geom.vline,
            Theme(default_color=color("black")),
            Guide.xlabel("Rank"), Guide.ylabel(""),
            Guide.title("σ[$i] = $(@sprintf("%0.3f", S[:S][i]))")),

        #Right singular vector
        plot(x=xv, y=sub(S[:Vt],i,:), ubars ? Geom.line : Geom.bar,
            Theme(default_color=rightcolors[i]),
            yintercept=[-1/√n, +1/√n], Geom.hline,
            Guide.xlabel("Record id"), Guide.ylabel(""),
            ubars ? Coord.Cartesian(xmin=minimum(xv), xmax=maximum(xv)) : Coord.Cartesian(xmin=0.5, xmax=n+0.5, ymin=-1.0, ymax=1.0),
            Guide.title("V[$i]")),
    )
end


