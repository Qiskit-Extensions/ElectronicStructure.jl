using FastBroadcast

####
#### Transformations to our representations
####

## Caution, we choose that this differs from OpenFermion by a factor of 1/2 in the two-body integral.
## In OpenFermion, they include the factor when constructing InteractionOperator.
## See spinorb_from_spatial in molecular_data.py.
"""
    spin_orbital_from_spatial(one_body_integrals, two_body_integrals; block_spin=false)

Create coefficients for spin-orbitals from coefficients for spatial orbitals only.

If `block_spin` is `true` the spins are in two sectors. Otherwise, the spin variable varies
more rapidly than the spatial variable, i.e. the spins are interleaved; orbitals
corresponding to the same spatial orbital, but with differing spins are adjacent.  Note that
Qiskit uses the former ordering and OpenFermion uses the latter.
"""
function spin_orbital_from_spatial(one_body_integrals, two_body_integrals; block_spin=false)
    spatial_dim = size(one_body_integrals)[1]
    spin_orb_dim = 2 * spatial_dim
    if block_spin
        r1 = 1:spatial_dim
        r2 = (spatial_dim+1):spin_orb_dim
    else # interleaved spin order
        r1 = 1:2:spin_orb_dim # odd indices
        r2 = 2:2:spin_orb_dim # even indices
    end
    return _spin_orbital_from_spatial(one_body_integrals, two_body_integrals, r1, r2)
end

function _spin_orbital_from_spatial(one_body_integrals, two_body_integrals, r1, r2)
    new_dim = 2 * size(one_body_integrals)[1]

    one_body_coefficients = zeros(eltype(one_body_integrals), (new_dim, new_dim))
    @.. one_body_coefficients[r1, r1] = one_body_integrals
    @.. one_body_coefficients[r2, r2] = one_body_integrals

    two_body_coefficients = zeros(eltype(two_body_integrals), ntuple(i->new_dim, 4))
    @inbounds for inds in ((r1, r2, r2, r1), (r2, r1, r1, r2), (r1, r1, r1, r1), (r2, r2, r2, r2))
       @.. two_body_coefficients[inds...] = two_body_integrals
    end
    @.. two_body_coefficients = two_body_coefficients / 2

    return ZChop.zchop!.((one_body_coefficients, two_body_coefficients))
end

"""
    struct InteractionOperator

Structure to represent a molecular Hamiltonian.
"""
struct InteractionOperator
    nuclear_repulsion::Float64
    one_body_tensor::Array{Float64, 2}
    two_body_tensor::Array{Float64, 4}
end

## NOTE !!!! Conversion of InteractionOperator to FermionOperator is in OF conversions.py
## !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
"""
    InteractionOperator(mol_data::MolecularData; block_spin=false, transform=:tophys)

Create an InteractionOperator from `mol_data`.

`mol_data` contains integrals for spatial orbitals. `InteractionOrbitals` creates coefficients for
spin orbitals, doubling the number of orbitals.

If `block_spin` is `true` the spins are in two sectors. Otherwise, the spin variable varies
more rapidly than the spatial variable, i.e. adjacent orbitals have differing spins. Note
that Qiskit uses the former ordering and OpenFermion uses the latter.

If `transform` is `:tophys`, it is assumed that the integrals in `mol_data` are stored in
chemists' order, and they are copied and converted to physicists' order before creating the
output operator. If `transform` is `:tochem`, they are transformed from physicists' to chemists' order.
If `transform` is `nothing`, no transformation is done.

The default values of `block_spin` and `transform` agree with the `InteractionOperator` from OpenFermion.
"""
function InteractionOperator(mol_data::MolecularData; block_spin=false, transform=:tophys)
    tb = mol_data.two_body_integrals
    if transform == :tochem
        tens_tmp = phys_to_chem(tb)
    elseif transform == :tophys
        tens_tmp = chem_to_phys(tb)
    elseif transform != nothing
        throw(ArgumentError("`transform` must be one of `:tochem`, `:tophys` or `nothing`"))
    else
        tens_tmp = tb
    end
    tens1, tens2 = spin_orbital_from_spatial(mol_data.one_body_integrals, tens_tmp, block_spin=block_spin)
    return InteractionOperator(mol_data.nuclear_repulsion, tens1, tens2)
end
